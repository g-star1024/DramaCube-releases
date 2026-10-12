import 'package:flutter/material.dart';

import 'tv_focus.dart';
import 'tv_theme.dart';

/// TV 陈列栏 —— 竖向列表内的横向焦点行（tv_focus.TvFocusRow 的语义化封装）。
///
/// 标题 + [TvFocusRow]（末项露出 30% + 兄弟压暗）。
class TvShelf extends StatelessWidget {
  final String title;
  final int itemCount;
  final void Function(int index)? onItemPressed;
  final Widget Function(BuildContext context, int index, bool focused) itemBuilder;
  final double rowHeight;

  const TvShelf({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.onItemPressed,
    this.rowHeight = 320,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TvSafeArea.left),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: TvColors.focus,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: TvColors.onSurface,
                    fontSize: TvText.title,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TvFocusRow(
            itemCount: itemCount,
            onItemPressed: onItemPressed,
            itemBuilder: itemBuilder,
            height: rowHeight,
          ),
        ],
      ),
    );
  }
}

/// TV 海报卡（陈列栏 / 网格通用）。
class TvPosterCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? coverURL;
  final bool focused;

  const TvPosterCard({
    super.key,
    required this.title,
    this.subtitle,
    this.coverURL,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: TvColors.surfaceHi,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused ? TvColors.focus : Colors.transparent,
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: coverURL != null && coverURL!.isNotEmpty
                  ? Image.network(
                      coverURL!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fallback(),
                    )
                  : _fallback(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: focused ? TvColors.focus : TvColors.onSurface,
            fontSize: TvText.caption,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: TvColors.muted, fontSize: 14),
          ),
      ],
    );
  }

  Widget _fallback() => const Center(
        child: Icon(Icons.movie_outlined, color: TvColors.muted, size: 40),
      );
}
