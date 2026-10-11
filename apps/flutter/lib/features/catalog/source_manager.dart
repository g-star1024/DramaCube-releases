import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/models.dart';

/// 视频源管理器（对齐 macOS 版 SourceManager）。
///
/// 订阅导入 / 站点列表 / 当前源 / 禁用状态 / 连通性测试。
final sourceManagerProvider = StateNotifierProvider<SourceManager, SourceState>((ref) {
  return SourceManager();
});

class SourceState {
  final List<TVBoxSite> sites;
  final String currentSource;
  final Set<String> disabled;
  final bool isImporting;
  final String? error;

  const SourceState({
    this.sites = const [],
    this.currentSource = '',
    this.disabled = const {},
    this.isImporting = false,
    this.error,
  });

  SourceState copyWith({
    List<TVBoxSite>? sites,
    String? currentSource,
    Set<String>? disabled,
    bool? isImporting,
    String? error,
  }) =>
      SourceState(
        sites: sites ?? this.sites,
        currentSource: currentSource ?? this.currentSource,
        disabled: disabled ?? this.disabled,
        isImporting: isImporting ?? this.isImporting,
        error: error ?? this.error,
      );

  /// 启用的站点（过滤禁用）。
  List<TVBoxSite> get enabledSites =>
      sites.where((s) => !disabled.contains(s.key)).toList();
}

class SourceManager extends StateNotifier<SourceState> {
  SourceManager() : super(const SourceState()) {
    _load();
  }

  static const _kSubscriptionURL = 'src.subscriptionURL';
  static const _kCurrentSource = 'src.current';
  static const _kDisabled = 'src.disabled';
  static const _kSites = 'src.sites';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
    },
  ));

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final sitesJson = prefs.getString(_kSites);
    List<TVBoxSite> sites = [];
    if (sitesJson != null) {
      try {
        final list = jsonDecode(sitesJson) as List;
        sites = list.map((e) => TVBoxSite.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    state = state.copyWith(
      sites: sites,
      currentSource: prefs.getString(_kCurrentSource) ?? (sites.isNotEmpty ? sites.first.key : ''),
      disabled: (prefs.getStringList(_kDisabled) ?? []).toSet(),
    );
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSites, jsonEncode(state.sites.map((s) => s.toJson()).toList()));
    await prefs.setString(_kCurrentSource, state.currentSource);
    await prefs.setStringList(_kDisabled, state.disabled.toList());
  }

  /// 导入订阅（TVBox 订阅 JSON / 单站点 JSON）。
  Future<bool> importSubscription(String url) async {
    state = state.copyWith(isImporting: true, error: null);
    try {
      final resp = await _dio.get(url);
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final sites = <TVBoxSite>[];
      if (data is Map && data['sites'] is List) {
        for (final s in data['sites']) {
          if (s is Map && s['key'] != null && s['api'] != null) {
            sites.add(TVBoxSite(
              key: s['key'].toString(),
              name: s['name']?.toString() ?? s['key'].toString(),
              api: s['api'].toString(),
            ));
          }
        }
      }
      if (sites.isEmpty) {
        state = state.copyWith(isImporting: false, error: '订阅无有效站点');
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSubscriptionURL, url);
      state = state.copyWith(
        sites: sites,
        currentSource: sites.first.key,
        isImporting: false,
      );
      await _persist();
      return true;
    } catch (e) {
      state = state.copyWith(isImporting: false, error: e.toString());
      return false;
    }
  }

  void setCurrentSource(String key) {
    state = state.copyWith(currentSource: key);
    _persist();
  }

  void toggleDisabled(String key) {
    final disabled = {...state.disabled};
    if (disabled.contains(key)) {
      disabled.remove(key);
    } else {
      disabled.add(key);
    }
    state = state.copyWith(disabled: disabled);
    _persist();
  }

  /// 连通性测试（首页 + 搜索双测，对齐 macOS 版 v2.1.2）。
  Future<bool> test(TVBoxSite site) async {
    try {
      await _dio.get(site.api, queryParameters: {'ac': 'videolist', 'pg': 1});
      await _dio.get(site.api, queryParameters: {'ac': 'videolist', 'wd': '电影', 'pg': 1});
      return true;
    } catch (_) {
      return false;
    }
  }
}
