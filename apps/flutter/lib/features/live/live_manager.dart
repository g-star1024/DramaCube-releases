import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/models.dart';

/// 直播源管理器（对齐 macOS 版 LiveEngine + LiveManager）。
///
/// 直播源 = 一个 m3u/m3u8 订阅地址（含 #EXTINF 元数据 + 流地址），
/// 也支持 txt 格式（频道名,URL，#genre# 分组）。
/// 多个源导入后按「频道名+分组」排重合并；可按源切换 + 连通性测试。
final liveManagerProvider = StateNotifierProvider<LiveManager, LiveState>((ref) {
  return LiveManager();
});

/// 直播源连通性探测结果。
class LiveHealth {
  final int? latencyMs;
  final bool ok;
  final DateTime checkedAt;

  const LiveHealth({required this.ok, this.latencyMs, required this.checkedAt});

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'ms': latencyMs,
        'at': checkedAt.millisecondsSinceEpoch,
      };

  static LiveHealth? fromJson(Map<String, dynamic> j) {
    final at = j['at'];
    if (at is! int) return null;
    return LiveHealth(
      ok: j['ok'] == true,
      latencyMs: j['ms'] is int ? j['ms'] as int : null,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

class LiveState {
  final List<LiveSource> sources;
  final List<LiveChannel> channels;
  final String currentSourceId; // '' = 全部源
  final Map<String, List<LiveChannel>> bySource; // 分源频道（切换用）
  final Map<String, LiveHealth> health;
  final bool isLoading;
  final String? error;

  const LiveState({
    this.sources = const [],
    this.channels = const [],
    this.currentSourceId = '',
    this.bySource = const {},
    this.health = const {},
    this.isLoading = false,
    this.error,
  });

  LiveState copyWith({
    List<LiveSource>? sources,
    List<LiveChannel>? channels,
    String? currentSourceId,
    Map<String, List<LiveChannel>>? bySource,
    Map<String, LiveHealth>? health,
    bool? isLoading,
    String? error,
  }) =>
      LiveState(
        sources: sources ?? this.sources,
        channels: channels ?? this.channels,
        currentSourceId: currentSourceId ?? this.currentSourceId,
        bySource: bySource ?? this.bySource,
        health: health ?? this.health,
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
      );

  /// 按分组整理频道。
  Map<String, List<LiveChannel>> get grouped {
    final map = <String, List<LiveChannel>>{};
    for (final ch in channels) {
      map.putIfAbsent(ch.group, () => []).add(ch);
    }
    return map;
  }

  /// 启用源按延迟排序（可用优先、延迟升序；未测试/失效靠后）。
  List<LiveSource> get sortedEnabledSources {
    final list = sources.where((s) => s.enabled).toList();
    int rank(LiveSource s) {
      final h = health[s.id];
      if (h == null) return 1;
      return h.ok ? 0 : 2;
    }

    list.sort((a, b) {
      final ra = rank(a);
      final rb = rank(b);
      if (ra != rb) return ra - rb;
      final la = health[a.id]?.latencyMs;
      final lb = health[b.id]?.latencyMs;
      if (la == null && lb == null) return 0;
      if (la == null) return 1;
      if (lb == null) return -1;
      return la - lb;
    });
    return list;
  }
}

class LiveManager extends StateNotifier<LiveState> {
  LiveManager() : super(const LiveState()) {
    _load();
  }

  static const _kSources = 'live.sources';
  static const _kCurrent = 'live.current';
  static const _kHealth = 'live.health';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// 探测专用 Dio（短超时）。
  final _probeDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kSources);
    List<LiveSource> sources = [];
    if (json != null) {
      try {
        final list = jsonDecode(json) as List;
        sources = list.map((e) => LiveSource.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    Map<String, LiveHealth> health = {};
    final healthJson = prefs.getString(_kHealth);
    if (healthJson != null) {
      try {
        final map = jsonDecode(healthJson) as Map<String, dynamic>;
        map.forEach((k, v) {
          if (v is Map<String, dynamic>) {
            final h = LiveHealth.fromJson(v);
            if (h != null) health[k] = h;
          }
        });
      } catch (_) {}
    }
    state = state.copyWith(
      sources: sources,
      currentSourceId: prefs.getString(_kCurrent) ?? '',
      health: health,
    );
    if (sources.any((s) => s.enabled)) {
      await refresh();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSources, jsonEncode(state.sources.map((s) => s.toJson()).toList()));
    await prefs.setString(_kCurrent, state.currentSourceId);
    await prefs.setString(
      _kHealth,
      jsonEncode(state.health.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// 添加直播源。
  Future<bool> addSource(String url, {String? name, String? userAgent}) async {
    final source = LiveSource(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      name: name ?? url,
      enabled: true,
      userAgent: userAgent,
    );
    state = state.copyWith(sources: [...state.sources, source]);
    await _persist();
    await refresh();
    return true;
  }

  /// 启用/禁用源。
  Future<void> setEnabled(String id, bool enabled) async {
    state = state.copyWith(
      sources: [
        for (final s in state.sources) s.id == id ? LiveSource(id: s.id, url: s.url, name: s.name, enabled: enabled, userAgent: s.userAgent) : s,
      ],
      // 禁用的正是当前源 → 回退到全部源。
      currentSourceId: !enabled && state.currentSourceId == id ? '' : state.currentSourceId,
    );
    await _persist();
    await refresh();
  }

  /// 删除直播源。
  Future<void> removeSource(String id) async {
    state = state.copyWith(
      sources: state.sources.where((s) => s.id != id).toList(),
      currentSourceId: state.currentSourceId == id ? '' : state.currentSourceId,
    );
    await _persist();
    await refresh();
  }

  /// 切换当前直播源（'' = 全部源合并）。
  Future<void> setCurrentSource(String id) async {
    if (state.currentSourceId == id) return;
    state = state.copyWith(
      currentSourceId: id,
      channels: _channelsFor(id),
    );
    await _persist();
  }

  List<LiveChannel> _channelsFor(String id) {
    if (id.isEmpty) {
      final merged = <LiveChannel>[];
      final seen = <String>{};
      for (final list in state.bySource.values) {
        for (final ch in list) {
          if (seen.add(ch.id)) merged.add(ch);
        }
      }
      return merged;
    }
    return state.bySource[id] ?? const [];
  }

  /// 直播源连通性探测（拉取订阅地址计时，8s 超时判失效）。
  Future<LiveHealth> probeSource(LiveSource source) async {
    final sw = Stopwatch()..start();
    try {
      await _probeDio.get(
        source.url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            if (source.userAgent != null) 'User-Agent': source.userAgent!,
          },
        ),
      );
      sw.stop();
      return LiveHealth(ok: true, latencyMs: sw.elapsedMilliseconds, checkedAt: DateTime.now());
    } catch (_) {
      sw.stop();
      return LiveHealth(ok: false, latencyMs: null, checkedAt: DateTime.now());
    }
  }

  /// 一键测试全部直播源：失效源自动禁用（全部失效时保留，避免无可用源）。
  Future<void> testAllSources() async {
    if (state.sources.isEmpty) return;
    final results = <String, LiveHealth>{};
    await Future.wait(state.sources.map((s) async {
      results[s.id] = await probeSource(s);
    }));
    if (!mounted) return;
    final enabled = state.sources.where((s) => s.enabled).toList();
    final failed = results.entries.where((e) => !e.value.ok).map((e) => e.key).toSet();
    final disableAll = failed.length >= enabled.length;
    final updated = <LiveSource>[
      for (final s in state.sources)
        if (!disableAll && s.enabled && failed.contains(s.id))
          LiveSource(id: s.id, url: s.url, name: s.name, enabled: false, userAgent: s.userAgent)
        else
          s,
    ];
    state = state.copyWith(
      sources: updated,
      health: results,
      // 当前源被禁用 → 回退到全部源。
      currentSourceId: !disableAll && failed.contains(state.currentSourceId) ? '' : state.currentSourceId,
    );
    await _persist();
    await refresh();
  }

  /// 刷新所有启用的源，拉取频道列表并合并排重。
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    final bySource = <String, List<LiveChannel>>{};
    for (final source in state.sources.where((s) => s.enabled)) {
      try {
        bySource[source.id] = await _fetchChannels(source);
      } catch (e) {
        state = state.copyWith(error: '拉取 ${source.name} 失败：$e');
      }
    }
    state = state.copyWith(
      bySource: bySource,
      channels: _channelsFor(state.currentSourceId),
      isLoading: false,
    );
  }

  Future<List<LiveChannel>> _fetchChannels(LiveSource source) async {
    final resp = await _dio.get(
      source.url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          if (source.userAgent != null) 'User-Agent': source.userAgent!,
        },
      ),
    );
    final text = resp.data as String;
    if (text.contains('#EXTINF')) {
      return _parseM3U(text);
    }
    return _parseTXT(text);
  }

  /// 解析 m3u：#EXTINF 元数据 + 下一行流地址。
  static List<LiveChannel> _parseM3U(String text) {
    final out = <LiveChannel>[];
    var pendingName = '';
    String? pendingLogo;
    var pendingGroup = '其他';
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.startsWith('#EXTINF')) {
        pendingName = line.split(',').last.trim();
        pendingLogo = _attr(line, 'tvg-logo');
        pendingGroup = _attr(line, 'group-title') ?? '其他';
        if (pendingGroup.isEmpty) pendingGroup = '其他';
      } else if (line.startsWith('http') && pendingName.isNotEmpty) {
        out.add(LiveChannel(
          id: '$pendingName|$pendingGroup',
          name: pendingName,
          logo: pendingLogo,
          group: pendingGroup,
          url: line,
        ));
        pendingName = '';
        pendingLogo = null;
      }
    }
    return out;
  }

  /// 解析 txt 直播源格式：分组名,#genre# / 频道名,URL。
  static List<LiveChannel> _parseTXT(String text) {
    final out = <LiveChannel>[];
    var group = '其他';
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#') && !line.contains('#genre#')) continue;
      if (line.contains('#genre#')) {
        final g = line.split(',').first.trim();
        group = g.isEmpty ? '其他' : g;
        continue;
      }
      final idx = line.indexOf(',');
      if (idx > 0) {
        final name = line.substring(0, idx).trim();
        final url = line.substring(idx + 1).trim();
        if (name.isNotEmpty && url.startsWith('http')) {
          out.add(LiveChannel(id: '$name|$group', name: name, group: group, url: url));
        }
      }
    }
    return out;
  }

  static String? _attr(String line, String key) {
    final pattern = RegExp('$key="([^"]*)"');
    final match = pattern.firstMatch(line);
    return match?.group(1);
  }
}
