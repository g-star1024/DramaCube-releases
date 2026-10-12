import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// NAS 视频首帧封面生成器（对齐 macOS 版 NASCoverGenerator）。
///
/// media_kit 播放到第 2 秒截首帧，磁盘缓存到 Application Support/DramaCube/nas-covers/。
/// 桌面/移动原生平台可用（Web 无本地文件系统与 mpv 截帧，回退占位图）。
///
/// 缓存键 = 视频播放地址的 FNV-1a 64bit（同一文件地址稳定，与 Swift 版同算法可互认）。
/// 并发限流 2，避免批量生成时 CPU/IO 打满；失败进黑名单避免对损坏文件反复尝试。
class NASCoverGenerator {
  NASCoverGenerator._();
  static final NASCoverGenerator shared = NASCoverGenerator._();

  static const _limit = 2;
  int _running = 0;
  final Queue<Completer<void>> _waiters = Queue();

  /// 生成失败的黑名单（避免对损坏/无视频轨文件反复尝试）。
  final Set<String> _failed = {};

  /// 正在生成中的 key（防止懒加载卡片滚回可见区重复触发同一视频的并发生成）。
  final Set<String> _inFlight = {};

  Directory? _cacheDir;

  Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/DramaCube/nas-covers');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  /// 播放地址 → 缓存键（FNV-1a 64bit，加版本前缀 v2 与 Swift 对齐；升级换前缀使旧缓存自然失效）。
  static String keyFor(String playURL) {
    const fnvPrime = 0x100000001b3;
    var hash = 0xcbf29ce484222325;
    for (final b in 'v2|$playURL'.codeUnits) {
      hash ^= b;
      hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// 取封面：命中缓存直接返回文件；否则后台生成并缓存；失败返回 null。
  /// [headers] 为 WebDAV Basic 鉴权等播放头（与播放器一致）。
  Future<File?> cover(String playURL, {Map<String, String> headers = const {}}) async {
    if (!_supported) return null;
    final key = keyFor(playURL);
    final dir = await _dir();
    final dest = File('${dir.path}/$key.jpg');
    if (await dest.exists()) return dest;
    if (_failed.contains(key)) return null;
    if (_inFlight.contains(key)) return null;

    await _acquire();
    try {
      if (await dest.exists()) return dest;
      _inFlight.add(key);
      final bytes = await _grabFrame(playURL, headers);
      if (bytes == null || bytes.isEmpty) {
        _failed.add(key);
        return null;
      }
      await dest.writeAsBytes(bytes, flush: true);
      return dest;
    } catch (_) {
      _failed.add(key);
      return null;
    } finally {
      _inFlight.remove(key);
      _release();
    }
  }

  /// 截第 2 秒首帧（JPEG 字节）。失败返回 null。
  Future<Uint8List?> _grabFrame(String playURL, Map<String, String> headers) async {
    final player = Player();
    try {
      await player.open(Media(playURL, httpHeaders: headers), play: false);
      await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 8));
      await player.seek(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 300));
      return await player.screenshot(format: 'image/jpeg')
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  static bool get _supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux || Platform.isAndroid || Platform.isIOS;

  // MARK: 并发闸门
  Future<void> _acquire() {
    if (_running < _limit) {
      _running++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _running--;
    }
  }
}
