import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/source_manager.dart';

/// 设置中心：TVBox 订阅导入 + 站点管理（M1），播放设置 / 数据备份（M2）。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _urlCtrl = TextEditingController();
  bool _testingKey = false;
  String? _testingSiteKey;
  final Map<String, bool?> _testResults = {};

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

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

  Future<void> _test(String key) async {
    setState(() {
      _testingKey = true;
      _testingSiteKey = key;
    });
    final sm = ref.read(sourceManagerProvider);
    final site = sm.sites.firstWhere((s) => s.key == key);
    final ok = await ref.read(sourceManagerProvider.notifier).test(site);
    if (!mounted) return;
    setState(() {
      _testResults[key] = ok;
      _testingKey = false;
      _testingSiteKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sm = ref.watch(sourceManagerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // MARK: TVBox 订阅导入
          _SectionHeader(title: 'TVBox 订阅'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => _import(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: sm.isImporting ? null : _import,
                      icon: sm.isImporting
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(sm.isImporting ? '导入中…' : '导入订阅'),
                    ),
                  ),
                  if (sm.error != null) ...[
                    const SizedBox(height: 8),
                    Text(sm.error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),

          // MARK: 站点管理
          if (sm.sites.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionHeader(title: '站点管理（${sm.sites.length}）'),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < sm.sites.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    _SiteTile(
                      site: sm.sites[i],
                      disabled: sm.disabled.contains(sm.sites[i].key),
                      isCurrent: sm.currentSource == sm.sites[i].key,
                      testing: _testingKey && _testingSiteKey == sm.sites[i].key,
                      testResult: _testResults[sm.sites[i].key],
                      onToggle: () => ref
                          .read(sourceManagerProvider.notifier)
                          .toggleDisabled(sm.sites[i].key),
                      onTest: () => _test(sm.sites[i].key),
                      onSetCurrent: () => ref
                          .read(sourceManagerProvider.notifier)
                          .setCurrentSource(sm.sites[i].key),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // MARK: 播放设置 / 数据备份（M2 占位）
          const SizedBox(height: 24),
          _SectionHeader(title: '其他'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text('播放设置'),
                  subtitle: const Text('默认倍速 / 跳片头 / 自动连播（M2）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('数据备份'),
                  subtitle: const Text('导出 / 导入本地数据（M2）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
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
      padding: const EdgeInsets.only(left: 4, bottom: 8),
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

class _SiteTile extends StatelessWidget {
  final dynamic site; // TVBoxSite
  final bool disabled;
  final bool isCurrent;
  final bool testing;
  final bool? testResult;
  final VoidCallback onToggle;
  final VoidCallback onTest;
  final VoidCallback onSetCurrent;

  const _SiteTile({
    required this.site,
    required this.disabled,
    required this.isCurrent,
    required this.testing,
    required this.testResult,
    required this.onToggle,
    required this.onTest,
    required this.onSetCurrent,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        isCurrent ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.grey,
      ),
      title: Text(
        site.name as String,
        style: TextStyle(color: disabled ? Colors.grey : null),
      ),
      subtitle: Text(
        site.api as String,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (testing)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else if (testResult != null)
            Icon(
              testResult! ? Icons.check_circle : Icons.error,
              size: 20,
              color: testResult! ? Colors.green : Colors.red,
            ),
          IconButton(
            icon: const Icon(Icons.wifi_tethering, size: 20),
            tooltip: '测试连通性',
            onPressed: testing ? null : onTest,
          ),
          Switch(value: !disabled, onChanged: (_) => onToggle()),
        ],
      ),
      onTap: onSetCurrent,
    );
  }
}
