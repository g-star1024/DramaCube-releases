/// TVBox 解析引擎（对齐 macOS 版 Swift TVBoxEngine）。
///
/// 支持 TVBox 采集站接口（ac=videolist / ac=detail / ac=list）。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

class TVBoxEngine {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    // 浏览器 UA（采集站防盗链，对齐 macOS 版）
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
    },
  ));

  /// 站点列表（订阅导入的站点，持久化到本地）。
  List<Map<String, String>> _sites = [];

  Future<List<Map<String, String>>> sites() async => _sites;

  /// 站点列表（ac=videolist 分类分页）。
  Future<List<dynamic>> list({required String site, int page = 1, String? typeId}) async {
    final api = _apiOf(site);
    if (api == null) return [];
    final params = {'ac': 'videolist', 'pg': page};
    if (typeId != null) params['t'] = typeId;
    final resp = await _dio.get(api, queryParameters: params);
    return _parseList(resp.data);
  }

  /// 剧集详情（ac=detail）。
  Future<Map<String, dynamic>> detail({required String site, required String vodId}) async {
    final api = _apiOf(site);
    if (api == null) return {};
    final resp = await _dio.get(api, queryParameters: {'ac': 'detail', 'ids': vodId});
    return _parseDetail(resp.data);
  }

  /// 站点搜索（ac=videolist&wd=）。
  Future<List<dynamic>> search({required String site, required String query}) async {
    final api = _apiOf(site);
    if (api == null) return [];
    final resp = await _dio.get(api, queryParameters: {'ac': 'videolist', 'wd': query, 'pg': 1});
    return _parseList(resp.data);
  }

  /// 订阅导入（TVBox 订阅 JSON / 单站点 JSON）。
  Future<Map<String, dynamic>> importSubscription(String url) async {
    try {
      final resp = await _dio.get(url);
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final sites = <Map<String, String>>[];
      if (data is Map && data['sites'] is List) {
        for (final s in data['sites']) {
          if (s is Map && s['key'] != null && s['api'] != null) {
            sites.add({
              'key': s['key'].toString(),
              'name': s['name']?.toString() ?? s['key'].toString(),
              'api': s['api'].toString(),
            });
          }
        }
      }
      _sites = sites;
      return {'ok': true, 'count': sites.length};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// 连通性测试（首页 + 搜索双测，对齐 macOS 版 v2.1.2）。
  Future<Map<String, dynamic>> test(String site) async {
    final api = _apiOf(site);
    if (api == null) return {'ok': false, 'error': '站点不存在'};
    // 双测：首页 8s + 搜索接口 8s，都通才 ok（假在线源会被自动禁用）
    try {
      await _dio.get(api, queryParameters: {'ac': 'videolist', 'pg': 1});
    } catch (e) {
      return {'ok': false, 'error': '首页超时/失败: $e'};
    }
    try {
      await _dio.get(api, queryParameters: {'ac': 'videolist', 'wd': '电影', 'pg': 1});
    } catch (e) {
      return {'ok': false, 'error': '搜索接口超时/失败: $e'};
    }
    return {'ok': true};
  }

  String? _apiOf(String siteKey) {
    for (final s in _sites) {
      if (s['key'] == siteKey) return s['api'];
    }
    return null;
  }

  List<dynamic> _parseList(dynamic data) {
    final json = data is String ? jsonDecode(data) : data;
    return json is Map && json['list'] is List ? json['list'] : [];
  }

  Map<String, dynamic> _parseDetail(dynamic data) {
    final json = data is String ? jsonDecode(data) : data;
    if (json is Map && json['list'] is List && (json['list'] as List).isNotEmpty) {
      return json['list'][0] as Map<String, dynamic>;
    }
    return {};
  }
}
