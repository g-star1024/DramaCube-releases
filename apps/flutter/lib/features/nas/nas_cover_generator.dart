import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/platform/app_log.dart';


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
      final short = playURL.length > 90 ? '${playURL.substring(0, 90)}…' : playURL;
      AppLog.app('封面生成开始 key=$key url=$short headers=${headers.keys.join(",")}');
      final bytes = await _grabFrame(playURL, headers);
      if (bytes == null || bytes.isEmpty) {
        _failed.add(key);
        AppLog.app('封面生成失败 key=$key（截帧空/超时/不支持）');
        return null;
      }
      await dest.writeAsBytes(bytes, flush: true);
      AppLog.app('封面生成成功 key=$key bytes=${bytes.length}');
      return dest;
    } catch (e) {
      _failed.add(key);
      AppLog.app('封面生成异常 key=$key err=$e');
      return null;
    } finally {
      _inFlight.remove(key);
      _release();
    }
  }

  /// 截第 2 秒首帧（JPEG 字节）。失败返回 null。
  ///
  /// v2.7.7 起改走外部进程截帧（根因修复）：
  /// media_kit 后台 Player 在 macOS 上对 WebDAV 远程流系统性超时（tracks/duration 事件
  /// 始终不来，全量 8s/15s 超时刷屏）；同一 URL 用外部 ffprobe/mpv 直接拉 1-3s 必出图。
  /// 优先 ffmpeg/ffprobe（系统 /usr/local/bin 常见），找不到再回退 media_kit（本地文件仍可用）。
  Future<Uint8List?> _grabFrame(String playURL, Map<String, String> headers) async {
    final isRemote = playURL.startsWith('http://') || playURL.startsWith('https://');
    if (isRemote) {
      final bytes = await _grabViaExternal(playURL, headers);
      if (bytes != null) return bytes;
      // 外部工具不可用时回退 media_kit（失败率高，仅兜底）。
      AppLog.app('外部截帧工具不可用/失败，回退 media_kit url=${playURL.length > 60 ? '${playURL.substring(0, 60)}…' : playURL}');
      return _grabViaMediaKit(playURL, headers);
    }
    return _grabViaMediaKit(playURL, headers);
  }

  /// 外部进程截帧：ffmpeg（优先）→ mpv。带鉴权 headers。
  Future<Uint8List?> _grabViaExternal(String playURL, Map<String, String> headers) async {
    final headerStr = headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join();
    // ffmpeg: -ss 2 快速 seek 到第 2 秒抽一帧 jpeg 到 stdout（pipe:1）。
    final ffmpeg = await _which('ffmpeg');
    if (ffmpeg != null) {
      final res = await _runFrame(ffmpeg, [
        '-hide_banner', '-loglevel', 'error',
        if (headerStr.isNotEmpty) ...['-headers', headerStr],
        '-ss', '2',
        '-i', playURL,
        '-frames:v', '1',
        '-f', 'image2pipe', '-vcodec', 'mjpeg', '-q:v', '3',
        'pipe:1',
      ]);
      if (res != null) return res;
    }
    final mpv = await _which('mpv');
    if (mpv != null) {
      // mpv 截图必须写文件（不支持 pipe），写到临时文件再读回。
      final tmp = File('${Directory.systemTemp.path}/dramacube-cover-${DateTime.now().microsecondsSinceEpoch}.jpg');
      try {
        final args = <String>[
          '--no-config', '--no-audio', '--quiet',
          if (headerStr.isNotEmpty) '--http-header-fields=$headerStr',
          '--start=2',
          '--frames=2',
          '--no-sub', '--no-osc', '--no-osd-bar',
          '--screenshot-format=jpg',
          '--screenshot-jpeg-quality=85',
          '--screenshot-directory=${tmp.parent.path}',
          '--screenshot-template=${tmp.path.replaceAll('${tmp.parent.path}/', '').replaceAll('.jpg', '')}',
          playURL,
        ];
        await Process.run(mpv, args).timeout(const Duration(seconds: 15));
        if (await tmp.exists()) {
          final b = await tmp.readAsBytes();
          if (b.isNotEmpty) return b;
        }
      } catch (_) {} finally {
        try { if (await tmp.exists()) await tmp.delete(); } catch (_) {}
      }
    }
    return null;
  }

  Future<Uint8List?> _runFrame(String bin, List<String> args) async {
    try {
      final proc = await Process.start(bin, args);
      final out = <int>[];
      proc.stdout.listen(out.addAll);
      final code = await proc.exitCode.timeout(const Duration(seconds: 15));
      if (code == 0 && out.isNotEmpty) return Uint8List.fromList(out);
    } catch (e) {
      AppLog.app('外部截帧异常 bin=$bin err=$e');
    }
    return null;
  }

  Future<String?> _which(String name) async {
    if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) return null;
    try {
      final res = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        [name],
      ).timeout(const Duration(seconds: 5));
      if (res.exitCode == 0) {
        final first = (res.stdout as String).trim().split('\n').first.trim();
        if (first.isNotEmpty) return first;
      }
    } catch (_) {}
    // 常见安装路径兜底（which 受 PATH 影响可能查不到）。
    for (final p in Platform.isWindows
        ? ['C:/Program Files/ffmpeg/bin/$name.exe']
        : ['/usr/local/bin/$name', '/opt/homebrew/bin/$name', '/usr/bin/$name']) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  /// media_kit 兜底截帧（本地文件 / 外部工具缺失场景）。
  Future<Uint8List?> _grabViaMediaKit(String playURL, Map<String, String> headers) async {
    final player = Player();
    try {
      await player.open(Media(playURL, httpHeaders: headers), play: false);
      // 等首个视频轨就绪（track 事件比 duration>0 更早、更稳）：
      // duration 需要 demuxer 读够索引才出，远程 WebDAV 上 track 先到。
      await player.stream.tracks
          .firstWhere((t) => t.video.isNotEmpty)
          .timeout(const Duration(seconds: 15));
      await player.seek(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 400));
      return await player.screenshot(format: 'image/jpeg')
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
    } catch (e) {
      AppLog.app('封面截帧异常 url=${playURL.length > 80 ? '${playURL.substring(0, 80)}…' : playURL} err=$e');
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
