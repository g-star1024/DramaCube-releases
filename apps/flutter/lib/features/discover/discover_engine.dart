import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings_provider.dart';
import '../../core/models/models.dart';

/// 发现页数据引擎 —— 移植 macOS 版 CoverEngine.swift。
///
/// 数据源：豆瓣「最近热门」（电影/剧集/综艺）+ B站番剧榜（动漫）。
/// 全部国内直连（dio 默认不走系统代理），内存缓存 TTL 跟随设置中心「内容缓存时长」。
final discoverEngineProvider = Provider<DiscoverEngine>(
    (ref) => DiscoverEngine(cacheHours: ref.watch(settingsProvider).cacheHours));

/// 豆瓣热门条目（对齐 macOS 版 DoubanHotItem）。
class DoubanHotItem {
  final String id;
  final String title;
  final String poster; // 豆瓣图（doubanio.com）
  final String rate; // 评分（可空）
  final String year;

  const DoubanHotItem({
    required this.id,
    required this.title,
    required this.poster,
    required this.rate,
    required this.year,
  });

  /// 转通用 Drama 模型（复用 PosterCard）。
  Drama toDrama(String kind) => Drama(
        id: 'douban|$kind|$id',
        title: title,
        coverURL: poster,
        remark: [year, rate.isNotEmpty ? '豆瓣 $rate' : ''].where((s) => s.isNotEmpty).join(' · '),
      );
}

/// 豆瓣条目详情（简介 + 副标题）。
class DoubanSubject {
  final String id;
  final String title;
  final String intro; // 剧情简介
  final String cardSubtitle; // 年代/地区/类型/导演/主演

  const DoubanSubject({
    required this.id,
    required this.title,
    required this.intro,
    required this.cardSubtitle,
  });
}

class DiscoverEngine {
  /// 内容缓存时长（小时），来自设置中心；改动后 Provider 重建、缓存自然清空。
  final int cacheHours;
  DiscoverEngine({this.cacheHours = 6});

  Duration get _hotTtl => Duration(hours: cacheHours);
  // 条目详情变更频率低，给 4 倍于列表的 TTL（原 6h/1h 比例保持）。
  Duration get _subjectTtl => Duration(hours: cacheHours * 4);

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
      'Referer': 'https://m.douban.com/',
    },
  ));

  final Map<String, (List<DoubanHotItem>, DateTime)> _hotCache = {};
  final Map<String, (DoubanSubject?, DateTime)> _subjectCache = {};

  // MARK: - 豆瓣「最近热门」

  /// 拉豆瓣最近热门。
  /// - kind: movie / tv
  /// - category: 热门 / tv / show（电影=热门，剧集=tv，综艺=show）
  /// - type: 全部 / tv / show
  Future<List<DoubanHotItem>> doubanHot({
    required String kind,
    required String category,
    required String type,
    int limit = 18,
    int start = 0,
  }) async {
    final key = '$kind|$category|$type|$limit|$start';
    final cached = _hotCache[key];
    if (cached != null && DateTime.now().difference(cached.$2) < _hotTtl) {
      return cached.$1;
    }
    try {
      final resp = await _dio.get(
        'https://m.douban.com/rexxar/api/v2/subject/recent_hot/$kind',
        queryParameters: {
          'start': start,
          'limit': limit,
          'category': category,
          'type': type,
        },
      );
      final items = resp.data['items'] as List? ?? [];
      final out = <DoubanHotItem>[];
      for (final it in items) {
        if (it is! Map) continue;
        final title = it['title']?.toString() ?? '';
        if (title.isEmpty) continue;
        var id = it['id']?.toString() ?? '';
        if (id.isEmpty && it['id'] is int) id = (it['id'] as int).toString();
        final pic = it['pic'];
        final poster = pic is Map
            ? (pic['normal']?.toString() ?? pic['large']?.toString() ?? '')
            : '';
        final rating = it['rating'];
        final rate = rating is Map ? (rating['value'] as num?)?.toStringAsFixed(1) ?? '' : '';
        final year = it['year']?.toString() ?? '';
        out.add(DoubanHotItem(
          id: id, title: title, poster: poster, rate: rate, year: year,
        ));
      }
      if (out.isNotEmpty) _hotCache[key] = (out, DateTime.now());
      return out.isNotEmpty ? out : (cached?.$1 ?? []);
    } catch (_) {
      return cached?.$1 ?? [];
    }
  }

  // MARK: - 豆瓣条目详情

  /// 拉豆瓣条目详情（rexxar movie/tv 条目接口），缓存跟随设置中心时长 ×4。
  Future<DoubanSubject?> doubanSubject({required String id, required String kind}) async {
    final key = '$kind|$id';
    final cached = _subjectCache[key];
    if (cached != null && DateTime.now().difference(cached.$2) < _subjectTtl) {
      return cached.$1;
    }
    final path = kind == 'tv' ? 'tv' : 'movie';
    try {
      final resp =
          await _dio.get('https://m.douban.com/rexxar/api/v2/$path/$id');
      final obj = resp.data as Map;
      final item = DoubanSubject(
        id: id,
        title: obj['title']?.toString() ?? '',
        intro: obj['intro']?.toString() ?? '',
        cardSubtitle: obj['card_subtitle']?.toString() ?? '',
      );
      _subjectCache[key] = (item, DateTime.now());
      return item;
    } catch (_) {
      return cached?.$1;
    }
  }

  // MARK: - B站番剧榜（发现页「热门动漫」）

  /// B站番剧三天榜（season_type=1 番剧，复用 DoubanHotItem 卡片）。
  Future<List<DoubanHotItem>> bilibiliBangumiRank({int limit = 54}) async {
    final realKey = 'bili|bangumi|$limit';
    final cached = _hotCache[realKey];
    if (cached != null && DateTime.now().difference(cached.$2) < _hotTtl) {
      return cached.$1;
    }
    try {
      final resp = await _dio.get(
        'https://api.bilibili.com/pgc/web/rank/list',
        queryParameters: {'season_type': 1, 'day': 3},
        options: Options(headers: {
          'Referer': 'https://www.bilibili.com',
          'User-Agent': 'Mozilla/5.0 (Macintosh) AppleWebKit/537.36',
        }),
      );
      final obj = resp.data as Map;
      if (obj['code'] != 0) return cached?.$1 ?? [];
      final list = (obj['result'] as Map?)?['list'] as List? ?? [];
      final out = <DoubanHotItem>[];
      for (final it in list.take(limit)) {
        if (it is! Map) continue;
        final title = it['title']?.toString() ?? '';
        if (title.isEmpty) continue;
        var poster = it['cover']?.toString() ?? '';
        if (poster.startsWith('http://')) {
          poster = 'https://${poster.substring('http://'.length)}';
        }
        var rate = it['rating']?.toString() ?? '';
        rate = rate.replaceAll('分', '');
        final seasonId = it['season_id']?.toString() ?? '';
        out.add(DoubanHotItem(
          id: seasonId, title: title, poster: poster, rate: rate, year: '',
        ));
      }
      if (out.isNotEmpty) _hotCache[realKey] = (out, DateTime.now());
      return out.isNotEmpty ? out : (cached?.$1 ?? []);
    } catch (_) {
      return cached?.$1 ?? [];
    }
  }

  // MARK: - 豆瓣海报回退（按标题）

  /// 标题归一化：去括号/季/年份/全N集/更新至，提高豆瓣命中率。
  static String normalize(String s) {
    var t = s.trim();
    t = t.replaceAll(RegExp(r'（.*?）|\(.*?\)'), '');
    t = t.replaceAll(RegExp(r'\s*(第?\d+季|[0-9]{4}年?|全\d+集|更新至.*)$'), '');
    return t.trim();
  }

  /// 按标题查豆瓣海报 URL（subject_suggest 轻量接口）。
  Future<String?> doubanPoster(String title) async {
    final key = normalize(title);
    if (key.isEmpty) return null;
    try {
      final resp = await _dio.get(
        'https://movie.douban.com/j/subject_suggest',
        queryParameters: {'q': key},
        options: Options(headers: {'Referer': 'https://movie.douban.com/'}),
      );
      final arr = resp.data as List;
      // 优先完全同名 + 有封面的条目
      for (final item in arr) {
        if (item is! Map) continue;
        final t = item['title']?.toString() ?? '';
        final img = item['img']?.toString() ?? '';
        if (img.isEmpty) continue;
        if (normalize(t) == key || t.contains(key) || key.contains(normalize(t))) {
          return img;
        }
      }
      for (final item in arr) {
        if (item is Map) {
          final img = item['img']?.toString() ?? '';
          if (img.isNotEmpty) return img;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
