import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 下载任务状态。
enum DownloadStatus { downloading, done, failed, cancelled }

/// 下载任务。
class DownloadTask {
  final String id; // dramaId:episodeId
  final String dramaId;
  final String title; // 剧名
  final String episodeTitle;
  final String url; // mp4 直链 / m3u8
  final String type; // mp4 / m3u8
  final String dirPath; // 保存目录（m3u8 = 分片目录）
  final String? coverURL;
  DownloadStatus status;
  int completed; // 完成分片/字节进度（mp4 用 0-1000 万分数）
  int total;
  String? error;
  DateTime updatedAt;

  DownloadTask({
    required this.id,
    required this.dramaId,
    required this.title,
    required this.episodeTitle,
    required this.url,
    required this.type,
    required this.dirPath,
    this.coverURL,
    this.status = DownloadStatus.downloading,
    this.completed = 0,
    this.total = 0,
    this.error,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  double get progress => total > 0 ? (completed / total).clamp(0.0, 1.0) : 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'dramaId': dramaId,
        'title': title,
        'episodeTitle': episodeTitle,
        'url': url,
        'type': type,
        'dirPath': dirPath,
        'coverURL': coverURL,
        'status': status.name,
        'completed': completed,
        'total': total,
        'error': error,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static DownloadTask fromJson(Map<String, dynamic> j) => DownloadTask(
        id: j['id'],
        dramaId: j['dramaId'],
        title: j['title'],
        episodeTitle: j['episodeTitle'],
        url: j['url'],
        type: j['type'],
        dirPath: j['dirPath'],
        coverURL: j['coverURL'],
        status: DownloadStatus.values.asNameMap()[j['status']] ?? DownloadStatus.failed,
        completed: j['completed'] ?? 0,
        total: j['total'] ?? 0,
        error: j['error'],
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
      );
}

/// 下载管理器 —— mp4 直链流式下载 + m3u8 分片并发下载（3 并发，断点续传：已存在分片跳过）。
class DownloadManager extends StateNotifier<List<DownloadTask>> {
  DownloadManager() : super([]) {
    _load();
  }

  static const _concurrency = 3;

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(minutes: 10),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15',
    },
  ));

  final Set<String> _cancelFlags = {};
  final Set<String> _running = {};

  Future<File> get _storeFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'downloads.json'));
  }

  Future<void> _load() async {
    try {
      final f = await _storeFile;
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        state = list
            .map((e) => DownloadTask.fromJson(e as Map<String, dynamic>))
            .toList();
        // 重启后 downloading → failed（可重试续传）
        for (final t in state) {
          if (t.status == DownloadStatus.downloading) {
            t.status = DownloadStatus.failed;
            t.error = '应用重启中断，可重试（已下载分片会跳过）';
          }
        }
        _persist();
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final f = await _storeFile;
      await f.writeAsString(jsonEncode(state.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }

  /// 新增下载任务（去重：同 id 未完成不重复下）。
  Future<void> enqueue({
    required String dramaId,
    required String episodeId,
    required String title,
    required String episodeTitle,
    required String url,
    String? coverURL,
  }) async {
    final id = '$dramaId:$episodeId';
    if (state.any((t) => t.id == id && t.status == DownloadStatus.downloading)) {
      return;
    }

    final base = await getApplicationDocumentsDirectory();
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeEp = episodeTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final dirPath = p.join(base.path, 'downloads', safeTitle, safeEp);
    await Directory(dirPath).create(recursive: true);

    final isM3u8 = url.contains('.m3u8');
    final task = DownloadTask(
      id: id,
      dramaId: dramaId,
      title: title,
      episodeTitle: episodeTitle,
      url: url,
      type: isM3u8 ? 'm3u8' : 'mp4',
      dirPath: dirPath,
      coverURL: coverURL,
    );
    state = [task, ...state];
    _persist();
    _run(task);
  }

  /// 取消任务。
  void cancel(String id) {
    _cancelFlags.add(id);
    _update(id, (t) {
      t.status = DownloadStatus.cancelled;
      t.updatedAt = DateTime.now();
    });
    _persist();
  }

  /// 重试（m3u8 已存在分片自动跳过 = 断点续传）。
  Future<void> retry(String id) async {
    final task = state.where((t) => t.id == id).firstOrNull;
    if (task == null || _running.contains(id)) return;
    _update(id, (t) {
      t.status = DownloadStatus.downloading;
      t.error = null;
      t.updatedAt = DateTime.now();
    });
    _persist();
    _run(task);
  }

  /// 删除任务（可选删除文件）。
  Future<void> remove(String id, {bool deleteFiles = true}) async {
    final task = state.where((t) => t.id == id).firstOrNull;
    if (task != null && deleteFiles) {
      try {
        final dir = Directory(task.dirPath);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
    state = state.where((t) => t.id != id).toList();
    _persist();
  }

  void _update(String id, void Function(DownloadTask) fn) {
    state = state.map((t) {
      if (t.id == id) fn(t);
      return t;
    }).toList();
  }

  Future<void> _run(DownloadTask task) async {
    if (_running.contains(task.id)) return;
    _running.add(task.id);
    _cancelFlags.remove(task.id);
    try {
      if (task.type == 'm3u8') {
        await _runM3u8(task);
      } else {
        await _runMp4(task);
      }
    } catch (e) {
      _update(task.id, (t) {
        if (t.status == DownloadStatus.downloading) {
          t.status = DownloadStatus.failed;
          t.error = e.toString();
          t.updatedAt = DateTime.now();
        }
      });
      _persist();
    } finally {
      _running.remove(task.id);
    }
  }

  // MARK: - mp4 直链

  Future<void> _runMp4(DownloadTask task) async {
    final resp = await _dio.get<ResponseBody>(
      task.url,
      options: Options(responseType: ResponseType.stream),
    );
    final contentLength = int.tryParse(resp.headers.value('content-length') ?? '') ?? 0;
    _update(task.id, (t) {
      t.total = 1000; // 千分比
      t.updatedAt = DateTime.now();
    });

    final file = File(p.join(task.dirPath, 'video.mp4'));
    final sink = file.openWrite();
    var received = 0;
    var lastTick = 0;
    await for (final chunk in resp.data!.stream) {
      if (_cancelFlags.contains(task.id)) {
        await sink.close();
        throw Exception('已取消');
      }
      received += chunk.length;
      sink.add(chunk);
      if (contentLength > 0) {
        final per = (received * 1000 ~/ contentLength);
        if (per != lastTick) {
          lastTick = per;
          _update(task.id, (t) {
            t.completed = per;
            t.updatedAt = DateTime.now();
          });
        }
      }
    }
    await sink.close();
    _update(task.id, (t) {
      t.status = DownloadStatus.done;
      t.completed = 1000;
      t.updatedAt = DateTime.now();
    });
    _persist();
  }

  // MARK: - m3u8 分片

  Future<void> _runM3u8(DownloadTask task) async {
    // 解析 playlist（master → 取第一个 variant）
    var playlistURL = task.url;
    var text = await _fetchText(playlistURL);
    if (text.contains('#EXT-X-STREAM-INF')) {
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('#EXT-X-STREAM-INF') && i + 1 < lines.length) {
          playlistURL = _resolve(lines[i + 1].trim(), playlistURL);
          text = await _fetchText(playlistURL);
          break;
        }
      }
    }
    final segments = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    if (segments.isEmpty) throw Exception('m3u8 无分片');

    _update(task.id, (t) {
      t.total = segments.length;
      t.updatedAt = DateTime.now();
    });

    // 已存在分片 = 续传
    var done = 0;
    final futures = <Future>[];
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        final i = cursor++;
        if (i >= segments.length) return;
        if (_cancelFlags.contains(task.id)) throw Exception('已取消');
        final segURL = _resolve(segments[i], playlistURL);
        final ext = p.extension(Uri.parse(segURL).path);
        final segFile = File(p.join(task.dirPath, 'seg${i.toString().padLeft(5, '0')}$ext'));
        if (await segFile.exists() && await segFile.length() > 0) {
          done++;
          continue;
        }
        final resp = await _dio.get<List<int>>(segURL,
            options: Options(responseType: ResponseType.bytes));
        await segFile.writeAsBytes(resp.data!);
        done++;
        _update(task.id, (t) {
          t.completed = done;
          t.updatedAt = DateTime.now();
        });
      }
    }

    for (var w = 0; w < _concurrency; w++) {
      futures.add(worker());
    }
    await Future.wait(futures);

    // 生成本地 index.m3u8（分片重写为本地文件名，mpv/播放器直接可播）
    final sb = StringBuffer('#EXTM3U\n#EXT-X-VERSION:3\n');
    for (var i = 0; i < segments.length; i++) {
      final segURL = _resolve(segments[i], playlistURL);
      final ext = p.extension(Uri.parse(segURL).path);
      sb.write('seg${i.toString().padLeft(5, '0')}$ext\n');
    }
    sb.write('#EXT-X-ENDLIST\n');
    await File(p.join(task.dirPath, 'index.m3u8')).writeAsString(sb.toString());

    _update(task.id, (t) {
      t.status = DownloadStatus.done;
      t.updatedAt = DateTime.now();
    });
    _persist();
  }

  Future<String> _fetchText(String url) async {
    final resp = await _dio.get<String>(url);
    return resp.data ?? '';
  }

  String _resolve(String ref, String base) {
    if (ref.startsWith('http://') || ref.startsWith('https://')) return ref;
    return Uri.parse(base).resolve(ref).toString();
  }
}

/// 下载管理 Provider。
final downloadManagerProvider =
    StateNotifierProvider<DownloadManager, List<DownloadTask>>((ref) {
  return DownloadManager();
});
