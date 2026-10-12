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
    final playUrl = vod['vod_play_url']?.toString() ?? '';
    final episodes = <Episode>[];
    // TVBox 格式：vod_play_url 是 "第1集$url1#第2集$url2"，多源用 $$$ 分隔
    final sources = playUrl.split('\$\$\$');
    if (sources.isNotEmpty) {
      final eps = sources.first.split('#');
      for (var i = 0; i < eps.length; i++) {
        final parts = eps[i].split('\$');
        if (parts.length == 2) {
          episodes.add(Episode(
            id: '$i',
            index: i + 1,
            title: parts[0],
            playURL: parts[1],
          ));
        }
      }
    }
    return DramaDetail(drama: drama, episodes: episodes);
  }
}
