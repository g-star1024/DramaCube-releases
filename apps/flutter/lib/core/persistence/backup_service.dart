import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database.dart';

/// 数据备份服务（对齐 macOS 版 v2.3.0 BackupService）。
///
/// 导出 SharedPreferences 全量设置 + drift 收藏/历史为 JSON 文件；
/// 导入时按类型恢复。
class BackupService {
  BackupService._();

  /// 导出到文件（系统保存面板）。
  static Future<String?> exportToFile() async {
    final payload = await _buildPayload();
    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出数据备份',
      fileName: 'dramacube-backup-${_timestamp()}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return null;
    await File(path).writeAsString(json);
    return path;
  }

  /// 从文件导入（系统打开面板）。
  static Future<String?> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入数据备份',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return null;
    final file = File(result.files.single.path!);
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    await _restorePayload(json);
    return file.path;
  }

  // MARK: 内部

  static Future<Map<String, dynamic>> _buildPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      settings[key] = prefs.get(key);
    }

    final db = AppDatabase();
    final favorites = await db.allFavorites();
    final histories = await db.allHistories();
    await db.close();

    return {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'appVersion': '2.3.0',
      'settings': settings,
      'favorites': [
        for (final f in favorites)
          {'dramaId': f.dramaId, 'title': f.title, 'coverURL': f.coverURL, 'addedAt': f.addedAt.toIso8601String()},
      ],
      'histories': [
        for (final h in histories)
          {
            'dramaId': h.dramaId,
            'episodeId': h.episodeId,
            'title': h.title,
            'episodeTitle': h.episodeTitle,
            'coverURL': h.coverURL,
            'position': h.position,
            'duration': h.duration,
            'updatedAt': h.updatedAt.toIso8601String(),
          },
      ],
    };
  }

  static Future<void> _restorePayload(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();

    // 恢复设置（按值类型写入）
    final settings = json['settings'] as Map<String, dynamic>? ?? {};
    for (final entry in settings.entries) {
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is double) {
        await prefs.setDouble(entry.key, value);
      } else if (value is String) {
        await prefs.setString(entry.key, value);
      } else if (value is List) {
        await prefs.setStringList(entry.key, value.map((e) => e.toString()).toList());
      }
    }

    // 恢复收藏/历史
    final db = AppDatabase();
    final favorites = json['favorites'] as List<dynamic>? ?? [];
    for (final f in favorites) {
      if (f is Map) {
        await db.toggleFavorite(
          f['dramaId']?.toString() ?? '',
          f['title']?.toString() ?? '',
          f['coverURL']?.toString(),
        );
      }
    }
    final histories = json['histories'] as List<dynamic>? ?? [];
    for (final h in histories) {
      if (h is Map) {
        await db.saveProgress(
          dramaId: h['dramaId']?.toString() ?? '',
          episodeId: h['episodeId']?.toString() ?? '',
          title: h['title']?.toString() ?? '',
          episodeTitle: h['episodeTitle']?.toString() ?? '',
          coverURL: h['coverURL']?.toString(),
          position: (h['position'] as num?)?.toDouble() ?? 0,
          duration: (h['duration'] as num?)?.toDouble() ?? 0,
        );
      }
    }
    await db.close();
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }
}
