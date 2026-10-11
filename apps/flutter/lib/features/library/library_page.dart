import 'package:flutter/material.dart';

/// 收藏/历史页（M1 实现收藏，M2 实现历史）。
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('收藏 / 历史（M1 实现收藏）', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
