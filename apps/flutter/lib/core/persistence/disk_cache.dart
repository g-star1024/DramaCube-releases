import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 轻量 JSON 磁盘缓存（对齐 Swift DiskCache）。
///
/// 存储位置：Application Support/DramaCube/cache/[safeKey].json
/// 文件格式：`{"at": epochMs, "value": 任意 JSON}`
/// 读：命中且未过期返回 value；过期返回 null（调用方决定先展示旧值还是重扫）。
/// 写：整文件原子覆盖（先写 .tmp 再 rename），失败静默（缓存是优化不是正确性依赖）。
class DiskCache {
  DiskCache._();
  static final DiskCache shared = DiskCache._();

  Directory? _dir;

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/DramaCube/cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// key 转安全文件名（保留字母数字，其余折叠为 _，限长防超长路径）。
  static String _safeKey(String key) {
    final s = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return s.length > 120 ? s.substring(0, 120) : s;
  }

  /// 读缓存：未过期返回解码后的 JSON 值，无缓存/过期/损坏返回 null。
  Future<dynamic> read(String key, {required Duration maxAge}) async {
    try {
      final dir = await _cacheDir();
      final f = File('${dir.path}/${_safeKey(key)}.json');
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return null;
      final at = j['at'];
      if (at is! int) return null;
      if (DateTime.now().millisecondsSinceEpoch - at > maxAge.inMilliseconds) {
        return null;
      }
      return j['value'];
    } catch (_) {
      return null;
    }
  }

  /// 读缓存（含过期旧值）：返回 (value, fresh)。无缓存返回 (null, false)。
  /// 用于「先展示旧缓存 + 后台静默刷新」的 stale-while-revalidate 语义。
  Future<(dynamic, bool)> readStale(String key, {required Duration maxAge}) async {
    try {
      final dir = await _cacheDir();
      final f = File('${dir.path}/${_safeKey(key)}.json');
      if (!await f.exists()) return (null, false);
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return (null, false);
      final at = j['at'];
      if (at is! int) return (null, false);
      final fresh =
          DateTime.now().millisecondsSinceEpoch - at <= maxAge.inMilliseconds;
      return (j['value'], fresh);
    } catch (_) {
      return (null, false);
    }
  }

  /// 写缓存（原子覆盖）。value 必须可被 jsonEncode 序列化。
  Future<void> write(String key, dynamic value) async {
    try {
      final dir = await _cacheDir();
      final f = File('${dir.path}/${_safeKey(key)}.json');
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'at': DateTime.now().millisecondsSinceEpoch,
        'value': value,
      }));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// 删除指定 key。
  Future<void> remove(String key) async {
    try {
      final dir = await _cacheDir();
      final f = File('${dir.path}/${_safeKey(key)}.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
