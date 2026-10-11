import 'package:flutter/material.dart';

/// 电视直播页（M2 实现）。
class LivePage extends StatelessWidget {
  const LivePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('电视直播')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tv_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('电视直播（M2 实现）', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
