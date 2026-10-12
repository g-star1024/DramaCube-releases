import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/models.dart';

/// NAS 资源库管理器（对齐 macOS 版 NASEngine + NASManager）。
///
/// webdav：PROPFIND 列目录，直链 HTTP GET 播放（带 Basic 鉴权）。
/// mount：本机已挂载目录（Windows 网络驱动器 / Linux mount），File 扫描。
final nasManagerProvider = StateNotifierProvider<NASManager, NASState>((ref) {
  return NASManager();
});

/// NAS 目录条目。
class NASEntry {
  final String name;
  final bool isDir;
  const NASEntry({required this.name, required this.isDir});
}

/// 资源库连通性探测结果。
class LibHealth {
  final int? latencyMs;
  final bool ok;
  final DateTime checkedAt;

  const LibHealth({required this.ok, this.latencyMs, required this.checkedAt});

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'ms': latencyMs,
        'at': checkedAt.millisecondsSinceEpoch,
      };

  static LibHealth? fromJson(Map<String, dynamic> j) {
    final at = j['at'];
    if (at is! int) return null;
    return LibHealth(
      ok: j['ok'] == true,
      latencyMs: j['ms'] is int ? j['ms'] as int : null,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

class NASState {
  final List<NASLibrary> libraries;
  final String currentLibraryId;
  final Map<String, LibHealth> health;
  final bool isLoading;
  final String? error;

  const NASState({
    this.libraries = const [],
    this.currentLibraryId = '',
    this.health = const {},
    this.isLoading = false,
    this.error,
  });

  NASState copyWith({
    List<NASLibrary>? libraries,
    String? currentLibraryId,
    Map<String, LibHealth>? health,
    bool? isLoading,
    String? error,
  }) =>
      NASState(
        libraries: libraries ?? this.libraries,
        currentLibraryId: currentLibraryId ?? this.currentLibraryId,
        health: health ?? this.health,
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
      );

  List<NASLibrary> get enabledLibraries => libraries.where((l) => l.enabled).toList();
}

class NASManager extends StateNotifier<NASState> {
  NASManager() : super(const NASState()) {
    _load();
  }

  static const _kLibraries = 'nas.libraries';
  static const _kCurrent = 'nas.current';
  static const _kHealth = 'nas.health';
  static const videoExts = {'mp4', 'mkv', 'mov', 'm4v', 'avi', 'wmv', 'flv', 'ts', 'm3u8'};

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kLibraries);
    List<NASLibrary> libs = [];
    if (json != null) {
      try {
        final list = jsonDecode(json) as List;
        libs = list.map((e) => NASLibrary.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    Map<String, LibHealth> health = {};
    final healthJson = prefs.getString(_kHealth);
    if (healthJson != null) {
      try {
        final map = jsonDecode(healthJson) as Map<String, dynamic>;
        map.forEach((k, v) {
          if (v is Map<String, dynamic>) {
            final h = LibHealth.fromJson(v);
            if (h != null) health[k] = h;
          }
        });
      } catch (_) {}
    }
    state = state.copyWith(
      libraries: libs,
      currentLibraryId: prefs.getString(_kCurrent) ?? '',
      health: health,
    );
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLibraries, jsonEncode(state.libraries.map((l) => l.toJson()).toList()));
    await prefs.setString(_kCurrent, state.currentLibraryId);
    await prefs.setString(
      _kHealth,
      jsonEncode(state.health.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// 切换当前资源库。
  Future<void> setCurrentLibrary(String id) async {
    if (state.currentLibraryId == id) return;
    state = state.copyWith(currentLibraryId: id);
    await _persist();
  }

  /// 资源库连通性探测（webdav PROPFIND 根目录 / mount 目录存在性，计时）。
  Future<LibHealth> probeLibrary(NASLibrary lib) async {
    final sw = Stopwatch()..start();
    try {
      if (lib.type == 'mount') {
        final dir = Directory(lib.baseURL);
        if (!await dir.exists()) throw StateError('目录不存在');
      } else {
        await _webdavList(lib, '');
      }
      sw.stop();
      return LibHealth(ok: true, latencyMs: sw.elapsedMilliseconds, checkedAt: DateTime.now());
    } catch (_) {
      sw.stop();
      return LibHealth(ok: false, latencyMs: null, checkedAt: DateTime.now());
    }
  }

  /// 一键测试全部资源库连通性（仅标记，不自动禁用）。
  Future<void> testAllLibraries() async {
    if (state.libraries.isEmpty) return;
    final results = <String, LibHealth>{};
    await Future.wait(state.libraries.map((l) async {
      results[l.id] = await probeLibrary(l);
    }));
    if (!mounted) return;
    state = state.copyWith(health: results);
    await _persist();
  }

  Future<void> addLibrary({
    required String name,
    required String type,
    required String baseURL,
    String? username,
    String? password,
  }) async {
    final lib = NASLibrary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      type: type,
      baseURL: baseURL,
      username: username,
      password: password,
      enabled: true,
    );
    state = state.copyWith(libraries: [...state.libraries, lib]);
    await _persist();
  }

  /// 更新资源库（编辑：保留 id，替换名称/类型/地址/凭据，enabled 不变）。
  /// 地址或凭据变更后旧缓存的连通性探测结果失效，清掉让用户重新测试。
  Future<void> updateLibrary(
    String id, {
    required String name,
    required String type,
    required String baseURL,
    String? username,
    String? password,
  }) async {
    state = state.copyWith(libraries: [
      for (final l in state.libraries)
        l.id == id
            ? NASLibrary(id: l.id, name: name, type: type, baseURL: baseURL,
                username: username, password: password, enabled: l.enabled)
            : l,
    ], health: Map.of(state.health)..remove(id));
    await _persist();
  }

  Future<void> removeLibrary(String id) async {
    state = state.copyWith(
      libraries: state.libraries.where((l) => l.id != id).toList(),
      currentLibraryId: state.currentLibraryId == id ? '' : state.currentLibraryId,
      health: Map.of(state.health)..remove(id),
    );
    await _persist();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    state = state.copyWith(libraries: [
      for (final l in state.libraries)
        l.id == id
            ? NASLibrary(id: l.id, name: l.name, type: l.type, baseURL: l.baseURL,
                username: l.username, password: l.password, enabled: enabled)
            : l,
    ], currentLibraryId: !enabled && state.currentLibraryId == id ? '' : state.currentLibraryId);
    await _persist();
  }

  NASLibrary? library(String id) {
    for (final l in state.libraries) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// 列出某路径下的直接子条目（不递归）。
  Future<List<NASEntry>> listEntries(NASLibrary lib, String path) async {
    if (lib.type == 'mount') {
      return _mountList(lib, path);
    }
    return _webdavList(lib, path);
  }

  /// 构造文件播放 URL（webdav 直链 / mount file://）。
  String fileURL(NASLibrary lib, String path) {
    if (lib.type == 'mount') {
      final root = lib.baseURL;
      return path.isEmpty ? root : '$root/$path';
    }
    // webdav：base/path（每段 URL 编码）
    final base = lib.baseURL.endsWith('/') ? lib.baseURL.substring(0, lib.baseURL.length - 1) : lib.baseURL;
    final esc = path.split('/').map(Uri.encodeComponent).join('/');
    return '$base/$esc';
  }

  /// 播放用 HTTP 头（webdav Basic 鉴权）。
  Map<String, String> playHeaders(NASLibrary lib) {
    if (lib.type == 'webdav' && lib.username != null && lib.username!.isNotEmpty) {
      final cred = base64Encode(utf8.encode('${lib.username}:${lib.password ?? ''}'));
      return {'Authorization': 'Basic $cred'};
    }
    return {};
  }

  static bool isVideo(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return videoExts.contains(ext);
  }

  // MARK: mount

  Future<List<NASEntry>> _mountList(NASLibrary lib, String path) async {
    final root = lib.baseURL;
    final dir = Directory(path.isEmpty ? root : '$root/$path');
    if (!await dir.exists()) return [];
    final out = <NASEntry>[];
    await for (final entity in dir.list()) {
      final name = entity.path.split('/').last;
      if (name.startsWith('.')) continue;
      out.add(NASEntry(name: name, isDir: entity is Directory));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  // MARK: WebDAV PROPFIND

  Future<List<NASEntry>> _webdavList(NASLibrary lib, String path) async {
    final base = lib.baseURL.endsWith('/') ? lib.baseURL.substring(0, lib.baseURL.length - 1) : lib.baseURL;
    final esc = path.split('/').map(Uri.encodeComponent).join('/');
    final urlStr = path.isEmpty ? '$base/' : '$base/$esc/';

    final headers = <String, dynamic>{
      'Depth': '1',
      'Content-Type': 'application/xml',
      ...playHeaders(lib),
    };

    final resp = await _dio.request(
      urlStr,
      options: Options(method: 'PROPFIND', headers: headers, responseType: ResponseType.plain),
      data: '<?xml version="1.0" encoding="utf-8"?>'
          '<D:propfind xmlns:D="DAV:">'
          '<D:prop><D:displayname/><D:resourcetype/></D:prop>'
          '</D:propfind>',
    );

    return _parseMultistatus(resp.data as String, Uri.parse(urlStr).path);
  }

  /// 解析 PROPFIND multistatus（正则轻量解析，对齐 macOS 版）。
  List<NASEntry> _parseMultistatus(String xml, String requestPath) {
    final out = <NASEntry>[];
    // <D:response> 块（兼容带命名空间前缀变体）
    final respPattern = RegExp(r'<(?:\w+:)?response[\s>][\s\S]*?</(?:\w+:)?response>');
    final hrefPattern = RegExp(r'<(?:\w+:)?href>([^<]+)</(?:\w+:)?href>');
    for (final match in respPattern.allMatches(xml)) {
      final block = match.group(0)!;
      final hrefMatch = hrefPattern.firstMatch(block);
      if (hrefMatch == null) continue;
      final href = hrefMatch.group(1)!;
      final isDir = block.contains('<D:collection') || block.contains(':collection');
      // 去掉自身
      var clean = href.endsWith('/') ? href.substring(0, href.length - 1) : href;
      var reqClean = requestPath.endsWith('/') ? requestPath.substring(0, requestPath.length - 1) : requestPath;
      if (clean == reqClean || clean.isEmpty) continue;
      final name = Uri.decodeComponent(clean.split('/').last);
      if (name.isEmpty || name.startsWith('.')) continue;
      out.add(NASEntry(name: name, isDir: isDir));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }
}
