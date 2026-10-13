import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/design_system.dart';
import '../../app/settings_provider.dart';
import '../../core/persistence/backup_service.dart';
import '../../core/platform/app_log.dart';
import '../catalog/source_manager.dart';

/// 设置中心 —— 分组：播放 / 浏览 / 通用 / 关于（对齐 macOS 版分组列表样式）。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _urlCtrl = TextEditingController();
  String? _backupMessage;
  bool _backupIsError = false;
  bool _checkingUpdate = false;
  String _updateMessage = '';

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  // MARK: 订阅导入 / 站点（原 M1 功能保留）

  Future<void> _import() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    final ok = await ref.read(sourceManagerProvider.notifier).importSubscription(url);
    if (!mounted) return;
    final err = ref.read(sourceManagerProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '订阅导入成功' : '导入失败：${err ?? "未知错误"}'),
    ));
    if (ok) _urlCtrl.clear();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlCtrl.text = data!.text!.trim();
    }
  }

  // MARK: 数据备份

  Future<void> _exportBackup() async {
    try {
      final path = await BackupService.exportToFile();
      if (!mounted) return;
      setState(() {
        _backupMessage = path != null ? '已导出到：$path' : '已取消';
        _backupIsError = false;
      });
    } catch (e) {
      setState(() {
        _backupMessage = '导出失败：$e';
        _backupIsError = true;
      });
    }
  }

  Future<void> _importBackup() async {
    try {
      final path = await BackupService.importFromFile();
      if (!mounted) return;
      setState(() {
        _backupMessage = path != null ? '导入成功，重启应用后生效' : '已取消';
        _backupIsError = false;
      });
    } catch (e) {
      setState(() {
        _backupMessage = '导入失败：$e';
        _backupIsError = true;
      });
    }
  }

  // MARK: 检查更新（GitHub Releases）

  Future<void> _checkUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _updateMessage = '';
    });
    try {
      final info = await PackageInfo.fromPlatform();
      final resp = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)))
          .get('https://api.github.com/repos/g-star1024/DramaCube-releases/releases/latest');
      final tag = resp.data['tag_name']?.toString() ?? '';
      final latest = tag.replaceFirst(RegExp(r'^v'), '');
      final current = info.version;
      if (!mounted) return;
      setState(() {
        _checkingUpdate = false;
        _updateMessage = _isNewer(latest, current)
            ? '发现新版本 v$latest（当前 v$current）'
            : '已是最新版本 v$current';
      });
      if (_isNewer(latest, current)) {
        _showUpdateDialog(latest, resp.data['body']?.toString() ?? '');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingUpdate = false;
        _updateMessage = '检查更新失败：网络错误';
      });
    }
  }

  bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final li = i < l.length ? l[i] : 0;
      final ci = i < c.length ? c[i] : 0;
      if (li != ci) return li > ci;
    }
    return false;
  }

  void _showUpdateDialog(String version, String notes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v$version'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            child: Text(
              notes.isEmpty ? '请前往发布页下载新版本。' : notes,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后再说')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(
                Uri.parse('https://github.com/g-star1024/DramaCube-releases/releases/latest'),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }

  // MARK: UI

  @override
  Widget build(BuildContext context) {
    final sm = ref.watch(sourceManagerProvider);
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          // MARK: 播放
          _SectionHeader(title: '播放'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: const Text('默认倍速'),
                  subtitle: const Text('每次起播时应用的倍速；播放器内临时调节不回写'),
                  trailing: Text(
                    '${settings.defaultRate}x',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  onTap: () => _pickOption(
                    title: '默认倍速',
                    options: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0],
                    label: (v) => '${v}x',
                    current: settings.defaultRate,
                    onSelect: settingsNotifier.setDefaultRate,
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  secondary: const Icon(Icons.autorenew),
                  title: const Text('自动连播'),
                  subtitle: const Text('一集播完自动播放下一集'),
                  value: settings.autoPlayNext,
                  onChanged: settingsNotifier.setAutoPlayNext,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.fast_forward),
                  title: const Text('跳过片头'),
                  subtitle: const Text('起播时自动跳到指定秒数'),
                  trailing: Text(
                    settings.introSkipSeconds > 0
                        ? '${settings.introSkipSeconds} 秒'
                        : '关闭',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  onTap: () => _pickOption(
                    title: '跳过片头',
                    options: [0, 30, 45, 60, 90],
                    label: (v) => v == 0 ? '关闭' : '$v 秒',
                    current: settings.introSkipSeconds,
                    onSelect: settingsNotifier.setIntroSkipSeconds,
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('缓冲策略'),
                  trailing: Text(
                    switch (settings.bufferStrategy) {
                      BufferStrategy.low => '省流',
                      BufferStrategy.medium => '均衡',
                      BufferStrategy.high => '流畅',
                    },
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  onTap: () => _pickOption(
                    title: '缓冲策略',
                    options: BufferStrategy.values,
                    label: (v) => switch (v) {
                      BufferStrategy.low => '省流（小缓冲）',
                      BufferStrategy.medium => '均衡（默认）',
                      BufferStrategy.high => '流畅（大缓冲）',
                    },
                    current: settings.bufferStrategy,
                    onSelect: settingsNotifier.setBufferStrategy,
                  ),
                ),
              ],
            ),
          ),

          // MARK: 浏览
          _SectionHeader(title: '浏览'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('外观'),
                  trailing: Text(
                    switch (settings.appearance) {
                      Appearance.system => '跟随系统',
                      Appearance.light => '浅色',
                      Appearance.dark => '深色',
                    },
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  onTap: () => _pickOption(
                    title: '外观',
                    options: Appearance.values,
                    label: (v) => switch (v) {
                      Appearance.system => '跟随系统',
                      Appearance.light => '浅色',
                      Appearance.dark => '深色',
                    },
                    current: settings.appearance,
                    onSelect: settingsNotifier.setAppearance,
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.color_lens_outlined),
                  title: const Text('配色主题'),
                  subtitle: const Text('五套色板一键切换，TV 焦点色同步'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppPalettes.byId(settings.paletteId).gradient,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AppPalettes.byId(settings.paletteId).name,
                        style: TextStyle(color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                  ),
                  onTap: _showPaletteSheet,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.grid_view_outlined),
                  title: const Text('界面缩放'),
                  subtitle: Slider(
                    value: settings.cardScale,
                    min: 0.8,
                    max: 1.4,
                    divisions: 6,
                    label: '${(settings.cardScale * 100).round()}%',
                    onChanged: settingsNotifier.setCardScale,
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('内容缓存时长'),
                  subtitle: const Text('发现页/详情缓存有效期'),
                  trailing: Text(
                    '${settings.cacheHours} 小时',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  onTap: () => _pickOption(
                    title: '内容缓存时长',
                    options: [1, 3, 6, 12, 24],
                    label: (v) => '$v 小时',
                    current: settings.cacheHours,
                    onSelect: settingsNotifier.setCacheHours,
                  ),
                ),
              ],
            ),
          ),

          // MARK: 通用
          _SectionHeader(title: '通用'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.tv_rounded),
                  title: const Text('电视模式'),
                  subtitle: const Text('影院深色 + 遥控焦点引擎（TV 独立版），重启后生效'),
                  value: settings.tvMode,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setTVMode(v),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('下载管理'),
                  subtitle: const Text('已下载剧集与任务进度'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/downloads'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.rss_feed),
                  title: const Text('TVBox 订阅导入'),
                  subtitle: const Text('导入订阅地址以添加视频源'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showSubscriptionSheet,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('导出数据'),
                  subtitle: const Text('设置 + 收藏 + 历史 → JSON 文件'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _exportBackup,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('导入数据'),
                  subtitle: const Text('从 JSON 备份文件恢复'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _importBackup,
                ),
                if (_backupMessage != null) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Row(
                      children: [
                        Icon(
                          _backupIsError ? Icons.error_outline : Icons.check_circle_outline,
                          size: 18,
                          color: _backupIsError
                              ? Theme.of(context).colorScheme.error
                              : Colors.green,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            _backupMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _backupIsError
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // MARK: 站点管理（入口 → 独立页，避免设置页被长列表拉爆）
          if (sm.sites.isNotEmpty) ...[
            _SectionHeader(title: '站点管理'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text('站点管理（${sm.sites.length}）'),
                subtitle: const Text('测速 / 开关 / 设当前源，失效源自动沉底'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/sites'),
              ),
            ),
          ],

          // MARK: 关于
          _SectionHeader(title: '关于'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update),
                  title: const Text('检查更新'),
                  subtitle: _updateMessage.isNotEmpty ? Text(_updateMessage) : null,
                  trailing: _checkingUpdate
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: _checkingUpdate ? null : _checkUpdate,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('运行日志'),
                  subtitle: const Text('查看 / 复制当日运行日志（播放器、网关、错误）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showLogSheet,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) => ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('剧立方 DramaCube'),
                    subtitle: Text('版本 ${snap.data?.version ?? '…'} · Flutter 全平台'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // MARK: 配色主题弹层

  void _showPaletteSheet() {
    final currentId = ref.read(settingsProvider).paletteId;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('配色主题', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: Spacing.md),
                for (final p in AppPalettes.all)
                  ListTile(
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: p.gradient,
                      ),
                    ),
                    title: Text(p.name),
                    subtitle: Text(switch (p.id) {
                      'hongguo' => '默认 · 暖阳奶油 + 粉金渐变（S1-S3 v2.5 基线）',
                      'rose' => '玫瑰金 · 暖调深红 + 金',
                      'blue' => '科技蓝 · 冷峻明快',
                      'forest' => '森林绿 · 自然清新',
                      'purple' => '暗夜紫 · 梦幻深邃',
                      _ => '',
                    }),
                    trailing: currentId == p.id
                        ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
                        : null,
                    onTap: () {
                      ref.read(settingsProvider.notifier).setPalette(p.id);
                      Navigator.pop(ctx);
                    },
                  ),
                const SizedBox(height: Spacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // MARK: 运行日志

  Future<void> _showLogSheet() async {
    AppLog.app('设置页打开运行日志');
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Row(
                  children: [
                    Text('运行日志', style: Theme.of(ctx).textTheme.titleMedium),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: '刷新',
                      onPressed: () => setState(() {}),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      tooltip: '复制日志',
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(ctx);
                        final navigator = Navigator.of(ctx);
                        final text = await AppLog.tail(500);
                        await Clipboard.setData(ClipboardData(text: text));
                        if (!mounted) return;
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(content: Text('已复制最近 500 行日志')),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_open, size: 20),
                      tooltip: '在 Finder 中显示',
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(ctx);
                        final ok = await AppLog.revealInFinder();
                        if (!mounted) return;
                        if (!ok) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('无法打开日志目录')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<String>(
                  future: AppLog.tail(300),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final lines = snap.data!.split('\n');
                    return ListView.builder(
                      padding: const EdgeInsets.all(Spacing.md),
                      itemCount: lines.length,
                      itemBuilder: (ctx, i) => SelectableText(
                        lines[i],
                        style: const TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: 通用选项弹层

  Future<void> _pickOption<T>({
    required String title,
    required List<T> options,
    required String Function(T) label,
    required T current,
    required ValueChanged<T> onSelect,
  }) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                ),
                for (final option in options)
                  ListTile(
                    title: Text(label(option)),
                    trailing: option == current
                        ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, option),
                  ),
                const SizedBox(height: Spacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) onSelect(picked);
  }

  // MARK: 订阅导入居中弹层（含站点管理摘要）

  void _showSubscriptionSheet() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 400),
          child: Container(
            decoration: BoxDecoration(
              color: Brand.background(Theme.of(ctx).brightness),
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                Text('TVBox 订阅导入', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: Spacing.lg),
                TextField(
                  controller: _urlCtrl,
                  decoration: InputDecoration(
                    labelText: '订阅地址',
                    hintText: 'https://…/tvbox.json',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste, size: 20),
                      tooltip: '粘贴',
                      onPressed: _paste,
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.md)),
                  ),
                  onSubmitted: (_) {
                    Navigator.pop(ctx);
                    _import();
                  },
                ),
                const SizedBox(height: Spacing.md),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _import();
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('导入订阅'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: Spacing.lg, bottom: Spacing.sm),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
