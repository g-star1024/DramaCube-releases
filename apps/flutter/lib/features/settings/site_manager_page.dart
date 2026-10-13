import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../core/widgets/health_badge.dart';
import '../catalog/source_manager.dart';

/// 站点管理独立页（从设置中心拆出，避免站点多时设置页被长列表拉爆）。
/// 排序：可用按延迟升序 → 未测试 → 失效 → 手动禁用沉底（sortedSites）。
class SiteManagerPage extends ConsumerStatefulWidget {
  const SiteManagerPage({super.key});

  @override
  ConsumerState<SiteManagerPage> createState() => _SiteManagerPageState();
}

class _SiteManagerPageState extends ConsumerState<SiteManagerPage> {
  bool _testingKey = false;
  String? _testingSiteKey;

  Future<void> _test(String key) async {
    setState(() {
      _testingKey = true;
      _testingSiteKey = key;
    });
    final sm = ref.read(sourceManagerProvider);
    final site = sm.sites.firstWhere((s) => s.key == key);
    await ref.read(sourceManagerProvider.notifier).probe(site);
    if (!mounted) return;
    setState(() {
      _testingKey = false;
      _testingSiteKey = null;
    });
  }

  /// 一键测试全部源：失效源自动禁用 + 按延迟排序。
  Future<void> _testAll() async {
    await ref.read(sourceManagerProvider.notifier).testAll();
    if (!mounted) return;
    final sm = ref.read(sourceManagerProvider);
    final failed = sm.sites.where((s) => sm.health[s.key]?.ok == false).length;
    final ok = sm.sites.length - failed;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('测试完成：$ok 个源可用，$failed 个失效源已自动禁用'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sm = ref.watch(sourceManagerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('站点管理（${sm.sites.length}）'),
        actions: [
          TextButton.icon(
            onPressed: sm.testingAll ? null : _testAll,
            icon: sm.testingAll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.speed, size: 18),
            label: Text(sm.testingAll ? '测试中…' : '一键测试'),
          ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: sm.sites.isEmpty
          ? const Center(child: Text('暂无站点，请先在设置页导入订阅', style: TextStyle(color: Colors.grey)))
          : ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < sm.sortedSites.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        _SiteTile(
                          site: sm.sortedSites[i],
                          disabled: sm.disabled.contains(sm.sortedSites[i].key),
                          isCurrent: sm.currentSource == sm.sortedSites[i].key,
                          testing:
                              _testingKey && _testingSiteKey == sm.sortedSites[i].key,
                          health: sm.health[sm.sortedSites[i].key],
                          onToggle: () => ref
                              .read(sourceManagerProvider.notifier)
                              .toggleDisabled(sm.sortedSites[i].key),
                          onTest: () => _test(sm.sortedSites[i].key),
                          onSetCurrent: () => ref
                              .read(sourceManagerProvider.notifier)
                              .setCurrentSource(sm.sortedSites[i].key),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SiteTile extends StatelessWidget {
  final dynamic site; // TVBoxSite
  final bool disabled;
  final bool isCurrent;
  final bool testing;
  final SiteHealth? health;
  final VoidCallback onToggle;
  final VoidCallback onTest;
  final VoidCallback onSetCurrent;

  const _SiteTile({
    required this.site,
    required this.disabled,
    required this.isCurrent,
    required this.testing,
    required this.health,
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
            const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            HealthBadge(
              tested: health != null,
              ok: health?.ok ?? false,
              latencyMs: health?.latencyMs,
            ),
          const SizedBox(width: 4),
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
