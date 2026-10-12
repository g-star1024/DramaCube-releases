import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 运行日志（对齐 Swift AppLog）：写 `~/Library/Logs/DramaCube/dramacube-flutter-YYYYMMDD.log`。
///
/// - 分类：app / net / player / error
/// - 8MB 滚动（保留一份 .1 备份），留 7 天
/// - 播放器/网关等关键点埋点，便于诊断「功能失灵 / 卡死 / 端口冲突」类问题
class AppLog {
  AppLog._();

  static File? _file;
  static IOSink? _sink;
  static bool _initialized = false;
  static final _queue = <String>[];
  static Timer? _flushTimer;

  /// 日志目录（macOS/Linux 桌面落盘；Android 用 ApplicationDocuments）。
  static Future<Directory> _logDir() async {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      final home = Platform.environment['HOME'] ?? '.';
      return Directory('$home/Library/Logs/DramaCube');
    }
    return getApplicationDocumentsDirectory();
  }

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final dir = await _logDir();
      await dir.create(recursive: true);
      final now = DateTime.now();
      final name =
          'dramacube-flutter-${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.log';
      _file = File('${dir.path}/$name');
      _rotateIfNeeded();
      _sink = _file!.openWrite(mode: FileMode.append);
      _flushTimer = Timer.periodic(const Duration(seconds: 2), (_) => _flush());
      _cleanupOld(dir);
      app('=== 启动 ${DateTime.now()} pid=$pid ===');
    } catch (e) {
      debugPrint('[AppLog] init 失败: $e');
    }
  }

  static void _rotateIfNeeded() {
    try {
      final f = _file!;
      if (!f.existsSync()) return;
      final len = f.lengthSync();
      if (len > 8 * 1024 * 1024) {
        final bak = File('${f.path}.1');
        if (bak.existsSync()) bak.deleteSync();
        f.renameSync(bak.path);
      }
    } catch (_) {}
  }

  static void _cleanupOld(Directory dir) {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        if (!e.path.contains('dramacube-flutter-')) continue;
        try {
          final m = e.lastModifiedSync();
          if (m.isBefore(cutoff)) e.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static void _write(String cat, String msg) {
    final ts = DateTime.now().toString().padRight(26);
    final line = '$ts [$cat] $msg\n';
    if (_sink != null) {
      _sink!.write(line);
    } else {
      _queue.add(line);
      // 未初始化前也打到控制台，防丢关键日志
      debugPrint('[AppLog/$cat] $msg');
    }
    // 每 100 行强制 flush 一次
    if (_queue.isNotEmpty && _sink != null) {
      for (final l in _queue) {
        _sink!.write(l);
      }
      _queue.clear();
    }
  }

  static void _flush() {
    try {
      _sink?.flush();
    } catch (_) {}
  }

  static void app(String msg) => _write('app', msg);
  static void net(String msg) => _write('net', msg);
  static void player(String msg) => _write('player', msg);
  static void error(String msg) => _write('error', msg);

  /// 读取最近 N 行日志（供设置页展示/复制）。
  static Future<String> tail([int lines = 200]) async {
    try {
      final f = _file;
      if (f == null || !await f.exists()) return '（日志文件不存在）';
      final content = await f.readAsString();
      final list = content.split('\n');
      final take = list.length > lines ? list.sublist(list.length - lines) : list;
      return take.join('\n');
    } catch (e) {
      return '读取日志失败: $e';
    }
  }

  /// 日志文件路径（供「在 Finder 中显示」）。
  static Future<String?> currentLogPath() async {
    try {
      if (_file != null) return _file!.path;
      final dir = await _logDir();
      final now = DateTime.now();
      final name =
          'dramacube-flutter-${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.log';
      final f = File('${dir.path}/$name');
      return await f.exists() ? f.path : null;
    } catch (_) {
      return null;
    }
  }

  /// 打开所在目录（macOS 用 `open -R` 高亮文件）。
  static Future<bool> revealInFinder() async {
    try {
      final path = await currentLogPath();
      if (path == null) return false;
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
        return true;
      } else if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', path.replaceAll('/', '\\')]);
        return true;
      } else {
        final dir = File(path).parent.path;
        await Process.run('xdg-open', [dir]);
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  static Future<void> dispose() async {
    _flushTimer?.cancel();
    _flush();
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
  }
}
