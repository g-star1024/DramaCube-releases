import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../core/widgets/cover_image.dart';
import 'download_manager.dart';

/// 下载管理页（任务列表 + 进度 + 重试/取消/删除/打开）。
class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadManagerProvider);
    final subtitle = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('下载管理')),
      body: tasks.isEmpty
          ? Center(
              child: Text('暂无下载任务\n在详情页选择集数即可下载',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: subtitle)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(Spacing.lg),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
              itemBuilder: (context, i) {
                final t = tasks[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          child: SizedBox(
                            width: 56,
                            height: 78,
                            child: CoverImage(url: t.coverURL, title: t.title),
                          ),
                        ),
                        const SizedBox(width: Spacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('${t.episodeTitle} · ${t.type.toUpperCase()}',
                                  style:
                                      TextStyle(fontSize: 12, color: subtitle)),
                              const SizedBox(height: Spacing.sm),
                              if (t.status == DownloadStatus.downloading) ...[
                                LinearProgressIndicator(
                                    value: t.total > 0 ? t.progress : null,
                                    minHeight: 4),
                                const SizedBox(height: 4),
                                Text(
                                  t.type == 'm3u8'
                                      ? '分片 ${t.completed}/${t.total}'
                                      : '${(t.progress * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(fontSize: 11, color: subtitle),
                                ),
                              ] else
                                Text(
                                  switch (t.status) {
                                    DownloadStatus.done => '已完成',
                                    DownloadStatus.failed =>
                                      '失败：${t.error ?? '未知错误'}',
                                    DownloadStatus.cancelled => '已取消',
                                    DownloadStatus.downloading => '下载中',
                                  },
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: t.status == DownloadStatus.done
                                          ? null
                                          : subtitle),
                                ),
                            ],
                          ),
                        ),
                        // 操作
                        _actions(context, ref, t),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _actions(BuildContext context, WidgetRef ref, DownloadTask t) {
    final mgr = ref.read(downloadManagerProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (t.status == DownloadStatus.downloading)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '取消',
            onPressed: () => mgr.cancel(t.id),
          ),
        if (t.status == DownloadStatus.failed || t.status == DownloadStatus.cancelled)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重试',
            onPressed: () => mgr.retry(t.id),
          ),
        if (t.status == DownloadStatus.done)
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: '打开',
            onPressed: () => _open(context, t),
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除',
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('删除任务'),
                content: const Text('删除任务并清除已下载的文件？'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
                ],
              ),
            );
            if (ok == true) await mgr.remove(t.id);
          },
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, DownloadTask t) async {
    // 本地播放：m3u8 → index.m3u8；mp4 → video.mp4
    final path = t.type == 'm3u8'
        ? '${t.dirPath}/index.m3u8'
        : '${t.dirPath}/video.mp4';
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      // 移动端用系统播放器打开
      return;
    }
    try {
      await Process.run('open', [path]);
    } catch (_) {
      try {
        await Process.run('xdg-open', [path]);
      } catch (_) {}
    }
  }
}
