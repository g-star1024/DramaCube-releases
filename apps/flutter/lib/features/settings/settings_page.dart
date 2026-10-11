import 'package:flutter/material.dart';

/// 设置中心（M1 实现订阅导入 + 播放设置，M2 实现数据备份）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.rss_feed),
              title: const Text('TVBox 订阅'),
              subtitle: const Text('导入视频源订阅地址'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // TODO: 订阅导入
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('播放设置'),
              subtitle: const Text('默认倍速 / 跳片头 / 自动连播'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // TODO: 播放设置
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('数据备份'),
              subtitle: const Text('导出 / 导入本地数据（M2 实现）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // TODO: 数据备份
              },
            ),
          ),
        ],
      ),
    );
  }
}
