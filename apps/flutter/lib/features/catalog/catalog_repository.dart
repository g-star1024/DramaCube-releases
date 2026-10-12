import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import 'source_manager.dart';

/// 视频源数据仓库（TVBox 列表/详情/搜索）。
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(ref);
});

class CatalogRepository {
  final Ref _ref;
  CatalogRepository(this._ref);

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
    },
  ));

  TVBoxSite? _site(String key) {
    final sites = _ref.read(sourceManagerProvider).sites;
    for (final s in sites) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// 站点分类（ac=list 的 `class` 字段，type_id → type_name；对齐 Swift fetchClasses）。
  ///
  /// 返回 [{type_id, type_name}]。`ac=videolist` 响应不带 class，必须用 ac=list。
  /// 部分站 class 为空时降级：从 videolist 翻页归并 type_id/type_name（对齐 Swift ②降级）。
  Future<List<Map<String, String>>> categories({required String siteKey}) async {
    final site = _site(siteKey);
    if (site == null) return [];
    // ① 优先 ac=list 的 class 字段
    try {
      final resp = await _dio.get(site.api, queryParameters: {'ac': 'list', 'pg': 1});
      final json = resp.data is String ? jsonDecode(resp.data) : resp.data;
      if (json is Map && json['class'] is List) {
        final out = <Map<String, String>>[];
        for (final c in json['class'] as List) {
          if (c is Map) {
            final id = c['type_id']?.toString() ?? '';
            final name = c['type_name']?.toString() ?? '';
            if (id.isNotEmpty && name.isNotEmpty) out.add({'type_id': id, 'type_name': name});
          }
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
    // ② 降级：videolist 翻页归并（最多 5 页，≥8 类或耗尽即停）
    final seen = <String, String>{};
    for (var page = 1; page <= 5; page++) {
      final vods = await list(siteKey: siteKey, page: page);
      if (vods.isEmpty) break;
      // list() 的 Drama 不含 type_id，需直接拉原始 vod
      try {
        final resp = await _dio.get(site.api, queryParameters: {'ac': 'videolist', 'pg': page});
        final json = resp.data is String ? jsonDecode(resp.data) : resp.data;
        final l = json is Map && json['list'] is List ? json['list'] as List : [];
        for (final v in l) {
          if (v is Map) {
            final id = v['type_id']?.toString() ?? '';
            final name = v['type_name']?.toString() ?? '';
            if (id.isNotEmpty && name.isNotEmpty && !seen.containsKey(id)) seen[id] = name;
          }
        }
        if (seen.length >= 8 || l.length < 20) break;
      } catch (_) {
        break;
      }
    }
    final out = seen.entries
        .map((e) => {'type_id': e.key, 'type_name': e.value})
        .toList()
      ..sort((a, b) => (int.tryParse(a['type_id']!) ?? 0).compareTo(int.tryParse(b['type_id']!) ?? 0));
    return out;
  }

  /// 站点列表（ac=videolist 分类分页）。
  Future<List<Drama>> list({required String siteKey, int page = 1, String? typeId}) async {
    final site = _site(siteKey);
    if (site == null) return [];
    final params = <String, dynamic>{'ac': 'videolist', 'pg': page};
    if (typeId != null) params['t'] = typeId;
    try {
      final resp = await _dio.get(site.api, queryParameters: params);
      final json = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = json is Map && json['list'] is List ? json['list'] as List : [];
      return list.map((e) => _dramaFromVod(siteKey, e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 剧集详情（ac=detail）。
  Future<DramaDetail?> detail({required String siteKey, required String vodId}) async {
    final site = _site(siteKey);
    if (site == null) return null;
    try {
      final resp = await _dio.get(site.api, queryParameters: {'ac': 'detail', 'ids': vodId});
      final json = resp.data is String ? jsonDecode(resp.data) : resp.data;
      if (json is Map && json['list'] is List && (json['list'] as List).isNotEmpty) {
        final vod = json['list'][0] as Map<String, dynamic>;
        return _detailFromVod(siteKey, vod);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 站点搜索（ac=videolist&wd=）。
  Future<List<Drama>> search({required String siteKey, required String query}) async {
    final site = _site(siteKey);
    if (site == null) return [];
    try {
      final resp = await _dio.get(site.api, queryParameters: {'ac': 'videolist', 'wd': query, 'pg': 1});
      final json = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = json is Map && json['list'] is List ? json['list'] as List : [];
      return list.map((e) => _dramaFromVod(siteKey, e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 跨源聚合搜索 —— 并发检索全部启用源，每完成一个源回调一次（流式呈现）。
  ///
  /// 对齐 macOS 版聚合搜索（8s 短超时 + 单源失败不影响整体）。
  void aggregateSearch({
    required String query,
    required void Function(String siteName, List<Drama> results) onSiteDone,
    VoidCallback? onAllDone,
  }) {
    final sites = _ref.read(sourceManagerProvider).enabledSites;
    if (sites.isEmpty) {
      onAllDone?.call();
      return;
    }
    var remaining = sites.length;
    for (final site in sites) {
      search(siteKey: site.key, query: query).then((results) {
        if (results.isNotEmpty) onSiteDone(site.name, results);
      }).catchError((_) {}).whenComplete(() {
        remaining--;
        if (remaining == 0) onAllDone?.call();
      });
    }
  }

  /// 站点显示名。
  String siteName(String siteKey) {
    for (final s in _ref.read(sourceManagerProvider).sites) {
      if (s.key == siteKey) return s.name;
    }
    return siteKey;
  }

  Drama _dramaFromVod(String siteKey, Map<String, dynamic> vod) {
    final id = 'tvbox|$siteKey|${vod['vod_id']}';
    return Drama(
      id: id,
      title: vod['vod_name']?.toString() ?? '',
      coverURL: vod['vod_pic']?.toString(),
      episodeCount: int.tryParse(vod['vod_remarks']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? ''),
      remark: vod['vod_remarks']?.toString(),
    );
  }

  DramaDetail _detailFromVod(String siteKey, Map<String, dynamic> vod) {
    final drama = _dramaFromVod(siteKey, vod);
    final episodes = parseEpisodes(vod);
    return DramaDetail(drama: drama, episodes: episodes);
  }

  /// 解析播放列表：`名称$URL#名称$URL`，多线路 `$$$` 分隔，**m3u8 线路优先**（对齐 Swift）。
  ///
  /// Swift 版两处关键（Flutter 之前缺失导致「Failed to recognize file format」）：
  /// ① 选线路不是无脑 first，而是优先选 vod_play_from 名或 URL 含 m3u8 的线路——
  ///    分享/解析类链接大多不可直接播，mpv 拿到 HTML/分享页才报「无法识别格式」。
  /// ② 单集按 `$` 拆分时 `parts.length >= 2`，URL 内可能含 `$`，用 join 还原，
  ///    不是 `== 2` 严格等（含 `$` 的 URL 会被误判丢弃整集）。
  static List<Episode> parseEpisodes(Map<String, dynamic> vod) {
    final playUrl = vod['vod_play_url']?.toString() ?? '';
    if (playUrl.isEmpty) return [];
    final lines = playUrl.split('\$\$\$');
    final froms = (vod['vod_play_from']?.toString() ?? '').split('\$\$\$');
    // 选线路：优先线路名或 URL 含 m3u8 的
    var chosenIdx = 0;
    for (var i = 0; i < lines.length; i++) {
      final from = i < froms.length ? froms[i].toLowerCase() : '';
      if (from.contains('m3u8') || lines[i].toLowerCase().contains('.m3u8')) {
        chosenIdx = i;
        break;
      }
    }
    if (chosenIdx >= lines.length) return [];
    final items = lines[chosenIdx].split('#').where((e) => e.isNotEmpty).toList();
    final eps = <Episode>[];
    for (var i = 0; i < items.length; i++) {
      final parts = items[i].split('\$');
      // URL 内可能含 $（签名参数），>=2 时把第 2 段起 join 还原完整 URL
      final url = parts.length >= 2
          ? parts.sublist(1).join('\$').trim()
          : '';
      final name = (parts.isNotEmpty ? parts.first.trim() : '') .isNotEmpty
          ? parts.first.trim()
          : '第${i + 1}集';
      if (!url.startsWith('http')) continue;
      eps.add(Episode(id: '$i', index: i + 1, title: name, playURL: url));
    }
    return eps;
  }
}
