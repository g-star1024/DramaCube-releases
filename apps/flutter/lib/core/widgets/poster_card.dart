import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../models/models.dart';
import 'cover_image.dart';

/// 海报卡 —— 3:4 封面 + 0.5 描边 + 标题 + 集数占位 + 评分角标。
///
/// 对齐 macOS 版 PosterCard 样式；可选收藏按钮/长按回调（U2 编辑模式用）。
class PosterCard extends StatelessWidget {
  final Drama drama;
  final double? rating;
  final bool showFavorite;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFavoriteToggle;

  const PosterCard({
    super.key,
    required this.drama,
    this.rating,
    this.showFavorite = false,
    this.isFavorite = false,
    this.onTap,
    this.onLongPress,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final text = brightness == Brightness.dark
        ? const Color(0xFFF0EBE4)
        : const Color(0xFF2A2620);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(Radius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radius.md),
                    border: Border.all(
                      color: Brand.separator(brightness),
                      width: 0.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radius.md),
                    child: CoverImage(url: drama.coverURL, title: drama.title),
                  ),
                ),
                // 评分角标（右上角）
                if (rating != null)
                  Positioned(
                    top: Spacing.xs,
                    right: Spacing.xs,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(Radius.sm),
                      ),
                      child: Text(
                        rating!.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                // 收藏按钮（可选）
                if (showFavorite)
                  Positioned(
                    top: Spacing.xs,
                    left: Spacing.xs,
                    child: _FavoriteButton(
                      isFavorite: isFavorite,
                      onTap: () => onFavoriteToggle?.call(!isFavorite),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  drama.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  drama.remark ??
                      (drama.episodeCount != null
                          ? '更新至 ${drama.episodeCount} 集'
                          : ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: text.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 收藏心形按钮（半透明圆底）。
class _FavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback onTap;

  const _FavoriteButton({required this.isFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          color: Colors.black38,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 16,
          color: isFavorite ? Brand.pinkDark : Colors.white,
        ),
      ),
    );
  }
}
