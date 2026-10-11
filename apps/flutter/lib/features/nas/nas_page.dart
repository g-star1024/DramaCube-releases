import 'package:flutter/material.dart';

/// NAS 资源库页（M2 实现）。
class NASPage extends StatelessWidget {
  const NASPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('资源库')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dns_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('NAS 资源库（M2 实现）', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
