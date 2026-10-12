import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/models.dart';

/// 视频源管理器（对齐 macOS 版 SourceManager）。
///
/// 订阅导入 / 站点列表 / 当前源 / 禁用状态 / 连通性测试（延迟计时 + 自动禁用）。
final sourceManagerProvider = StateNotifierProvider<SourceManager, SourceState>((ref) {
  return SourceManager();
});

/// 单站点连通性探测结果。
class SiteHealth {
  final int? latencyMs; // 成功时往返毫秒数；失败为 null
  final bool ok;
  final DateTime checkedAt;

  const SiteHealth({required this.ok, this.latencyMs, required this.checkedAt});

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'ms': latencyMs,
        'at': checkedAt.millisecondsSinceEpoch,
      };

  static SiteHealth? fromJson(Map<String, dynamic> j) {
    final at = j['at'];
    if (at is! int) return null;
    return SiteHealth(
      ok: j['ok'] == true,
      latencyMs: j['ms'] is int ? j['ms'] as int : null,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

class SourceState {
  final List<TVBoxSite> sites;
  final String currentSource;
  final Set<String> disabled;
  final bool isImporting;
  final String? error;
  final Map<String, SiteHealth> health;
  final bool pinned; // 用户手动指定过当前源（false = 自动跟随最快源）
  final bool testingAll; // 一键测试进行中

  const SourceState({
    this.sites = const [],
    this.currentSource = '',
    this.disabled = const {},
    this.isImporting = false,
    this.error,
    this.health = const {},
    this.pinned = false,
    this.testingAll = false,
  });

  SourceState copyWith({
    List<TVBoxSite>? sites,
    String? currentSource,
    Set<String>? disabled,
    bool? isImporting,
    String? error,
    Map<String, SiteHealth>? health,
    bool? pinned,
    bool? testingAll,
  }) =>
      SourceState(
        sites: sites ?? this.sites,
        currentSource: currentSource ?? this.currentSource,
        disabled: disabled ?? this.disabled,
        isImporting: isImporting ?? this.isImporting,
        error: error ?? this.error,
        health: health ?? this.health,
        pinned: pinned ?? this.pinned,
        testingAll: testingAll ?? this.testingAll,
      );

  /// 启用的站点（过滤禁用）。
  List<TVBoxSite> get enabledSites =>
      sites.where((s) => !disabled.contains(s.key)).toList();

  /// 启用站点按延迟排序：可用源（延迟升序）→ 未测试 → 失效。
  List<TVBoxSite> get sortedEnabledSites {
    final list = enabledSites;
    int rank(TVBoxSite s) {
      final h = health[s.key];
      if (h == null) return 1;
      return h.ok ? 0 : 2;
    }

    list.sort((a, b) {
      final ra = rank(a);
      final rb = rank(b);
      if (ra != rb) return ra - rb;
      final la = health[a.key]?.latencyMs;
      final lb = health[b.key]?.latencyMs;
      if (la == null && lb == null) return 0;
      if (la == null) return 1;
      if (lb == null) return -1;
      return la - lb;
    });
    return list;
  }

  /// 延迟最低的可用源（无可用源时返回 null）。
  TVBoxSite? get fastestSite {
    for (final s in sortedEnabledSites) {
      final h = health[s.key];
      if (h != null && h.ok) return s;
    }
    return null;
  }
}

class SourceManager extends StateNotifier<SourceState> {
  /// [probeDio] 仅供测试注入（假适配器）；生产环境默认内部构造。
  SourceManager({Dio? probeDio})
      : _probeDio = probeDio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              headers: {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
              },
            )),
        super(const SourceState()) {
    _load();
  }

  static const _kSubscriptionURL = 'src.subscriptionURL';
  static const _kCurrentSource = 'src.current';
  static const _kDisabled = 'src.disabled';
  static const _kSites = 'src.sites';
  static const _kHealth = 'src.health';
  static const _kPinned = 'src.pinned';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
    },
  ));

  /// 探测专用 Dio（短超时，快速判定失效）。
  final Dio _probeDio;

  bool _autoProbed = false; // 本次启动是否已自动探测过

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
    Map<String, SiteHealth> health = {};
    final healthJson = prefs.getString(_kHealth);
    if (healthJson != null) {
      try {
        final map = jsonDecode(healthJson) as Map<String, dynamic>;
        map.forEach((k, v) {
          if (v is Map<String, dynamic>) {
            final h = SiteHealth.fromJson(v);
            if (h != null) health[k] = h;
          }
        });
      } catch (_) {}
    }
    state = state.copyWith(
      sites: sites,
      currentSource: prefs.getString(_kCurrentSource) ?? (sites.isNotEmpty ? sites.first.key : ''),
      disabled: (prefs.getStringList(_kDisabled) ?? []).toSet(),
      health: health,
      pinned: prefs.getBool(_kPinned) ?? false,
    );
    // 自愈：历史数据里的空/失效当前源（旧版本会持久化空键）恢复为可用源，
    // 避免空 siteKey 让下游静默返回空 → 全站无可播放内容。
    final healed = _resolveCurrentKey();
    if (healed != state.currentSource) {
      state = state.copyWith(currentSource: healed);
      await _persist();
    }
    // 首次启动（无历史探测数据）时后台自动测速，让默认源 = 延迟最低的源。
    if (!_autoProbed && sites.isNotEmpty && health.isEmpty) {
      _autoProbed = true;
      testAll();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSites, jsonEncode(state.sites.map((s) => s.toJson()).toList()));
    await prefs.setString(_kCurrentSource, state.currentSource);
    await prefs.setStringList(_kDisabled, state.disabled.toList());
    await prefs.setBool(_kPinned, state.pinned);
    await prefs.setString(
      _kHealth,
      jsonEncode(state.health.map((k, v) => MapEntry(k, v.toJson()))),
    );
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
        pinned: false,
        health: const {},
        isImporting: false,
      );
      await _persist();
      // 导入后立即测速：默认展示延迟最低的源。
      testAll();
      return true;
    } catch (e) {
      state = state.copyWith(isImporting: false, error: e.toString());
      return false;
    }
  }

  /// 手动切换当前源（用户设置优先，后续不再自动跟随）。
  void setCurrentSource(String key) {
    if (state.currentSource == key && state.pinned) return;
    state = state.copyWith(currentSource: key, pinned: true);
    _persist();
  }

  /// 自动选择延迟最低的可用源（仅在用户未手动指定过时生效）。
  ///
  /// fastestSite 为空（探测全失败/未测）时回退第一个启用源，
  /// 保证当前源永不为空（空键会让下游静默返回空）。
  void autoSelectFastest() {
    if (state.pinned) return;
    final target = state.fastestSite?.key ?? _firstEnabledKey();
    if (target == null || state.currentSource == target) return;
    state = state.copyWith(currentSource: target);
    _persist();
  }

  /// 解析一个可用的当前源键：当前仍有效 → 最快可用 → 第一个启用 → 第一个站点。
  /// 仅当无任何站点时才返回 ''。
  String _resolveCurrentKey() {
    final s = state;
    if (s.currentSource.isNotEmpty &&
        s.sites.any((x) => x.key == s.currentSource) &&
        !s.disabled.contains(s.currentSource)) {
      return s.currentSource;
    }
    final fastest = s.fastestSite?.key;
    if (fastest != null) return fastest;
    final firstEnabled = _firstEnabledKey();
    if (firstEnabled != null) return firstEnabled;
    return s.sites.isNotEmpty ? s.sites.first.key : '';
  }

  String? _firstEnabledKey() {
    final enabled = state.enabledSites;
    return enabled.isNotEmpty ? enabled.first.key : null;
  }

  void toggleDisabled(String key) {
    final disabled = {...state.disabled};
    if (disabled.contains(key)) {
      disabled.remove(key);
    } else {
      disabled.add(key);
    }
    state = state.copyWith(disabled: disabled);
    // 当前源被禁用/失效时切到可用源；有站点时绝不留空键。
    state = state.copyWith(currentSource: _resolveCurrentKey());
    _persist();
  }

  /// 单站点连通性探测（首页接口计时，6s 超时判失效）。
  Future<SiteHealth> probe(TVBoxSite site) async {
    final sw = Stopwatch()..start();
    try {
      await _probeDio.get(site.api, queryParameters: {'ac': 'videolist', 'pg': 1});
      sw.stop();
      return SiteHealth(ok: true, latencyMs: sw.elapsedMilliseconds, checkedAt: DateTime.now());
    } catch (_) {
      sw.stop();
      return SiteHealth(ok: false, latencyMs: null, checkedAt: DateTime.now());
    }
  }

  /// 一键测试全部源：并发计时 → 失效源自动禁用 → 按延迟自动排序（未手动指定时切到最快源）。
  Future<void> testAll() async {
    if (state.sites.isEmpty || state.testingAll) return;
    state = state.copyWith(testingAll: true);
    final pending = <Future<void>>[];
    for (final site in state.sites) {
      pending.add(probe(site).then((h) {
        if (!mounted) return;
        state = state.copyWith(health: {...state.health, site.key: h});
      }));
    }
    await Future.wait(pending);
    if (!mounted) return;

    // 失效源自动禁用（若全部失效则保留，避免无可用源）。
    final failed = state.sites.where((s) => state.health[s.key]?.ok == false).map((s) => s.key).toSet();
    final disabled = {...state.disabled, ...failed};
    if (disabled.length >= state.sites.length) {
      disabled.removeAll(failed);
    }
    // 当前源：未手动指定过 → 跟随最快；手动指定过但已失效 → 也切最快。
    var current = state.currentSource;
    if (!state.pinned || disabled.contains(current)) {
      current = state.fastestSite?.key ?? current;
    }
    state = state.copyWith(disabled: disabled, currentSource: current, testingAll: false);
    // 保底：有站点时 currentSource 不允许为空（空键会让下游静默返回空 → 全站无可播放内容）。
    state = state.copyWith(currentSource: _resolveCurrentKey());
    await _persist();
  }
}
