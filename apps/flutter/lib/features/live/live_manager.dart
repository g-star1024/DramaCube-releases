import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/models.dart';

/// 直播源管理器（对齐 macOS 版 LiveEngine + LiveManager）。
///
/// 直播源 = 一个 m3u/m3u8 订阅地址（含 #EXTINF 元数据 + 流地址），
/// 也支持 txt 格式（频道名,URL，#genre# 分组）。
/// 多个源导入后按「频道名+分组」排重合并。
final liveManagerProvider = StateNotifierProvider<LiveManager, LiveState>((ref) {
  return LiveManager();
});

class LiveState {
  final List<LiveSource> sources;
  final List<LiveChannel> channels;
  final bool isLoading;
  final String? error;

  const LiveState({
    this.sources = const [],
    this.channels = const [],
    this.isLoading = false,
    this.error,
  });

  LiveState copyWith({
    List<LiveSource>? sources,
    List<LiveChannel>? channels,
    bool? isLoading,
    String? error,
  }) =>
      LiveState(
        sources: sources ?? this.sources,
        channels: channels ?? this.channels,
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
}

class LiveManager extends StateNotifier<LiveState> {
  LiveManager() : super(const LiveState()) {
    _load();
  }

  static const _kSources = 'live.sources';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
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
    state = state.copyWith(sources: sources);
    if (sources.any((s) => s.enabled)) {
      await refresh();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSources, jsonEncode(state.sources.map((s) => s.toJson()).toList()));
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

  /// 删除直播源。
  Future<void> removeSource(String id) async {
    state = state.copyWith(sources: state.sources.where((s) => s.id != id).toList());
    await _persist();
    await refresh();
  }

  /// 启用/禁用源。
  Future<void> setEnabled(String id, bool enabled) async {
    state = state.copyWith(
      sources: [
        for (final s in state.sources) s.id == id ? LiveSource(id: s.id, url: s.url, name: s.name, enabled: enabled, userAgent: s.userAgent) : s,
      ],
    );
    await _persist();
    await refresh();
  }

  /// 刷新所有启用的源，拉取频道列表并合并排重。
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    final all = <LiveChannel>[];
    final seen = <String>{};
    for (final source in state.sources.where((s) => s.enabled)) {
      try {
        final channels = await _fetchChannels(source);
        for (final ch in channels) {
          if (seen.add(ch.id)) all.add(ch);
        }
      } catch (e) {
        state = state.copyWith(error: '拉取 ${source.name} 失败：$e');
      }
    }
    state = state.copyWith(channels: all, isLoading: false);
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
