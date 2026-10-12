import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/design_system.dart';

/// 封面组件 —— cached_network_image + 暖沙占位 + 标题首字回退。
///
/// 对齐 macOS 版封面占位风格（暖沙底 + 播放图标）。
class CoverImage extends StatelessWidget {
  final String? url;
  final String title;
  final BoxFit fit;
  final Map<String, String>? httpHeaders;

  const CoverImage({
    super.key,
    required this.url,
    required this.title,
    this.fit = BoxFit.cover,
    this.httpHeaders,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final placeholderColor = Brand.placeholder(brightness);

    if (url == null || url!.isEmpty) {
      return _fallback(placeholderColor);
    }

    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      httpHeaders: httpHeaders,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => _fallback(placeholderColor),
      errorWidget: (_, __, ___) => _fallback(placeholderColor),
    );
  }

  /// 暖沙底 + 剧名首字 / 播放图标回退。
  Widget _fallback(Color color) {
    final first = title.trim().isEmpty ? '' : title.trim().characters.first;
    return Container(
      color: color,
      alignment: Alignment.center,
      child: first.isEmpty
          ? Icon(Icons.play_circle_outline,
              size: 36, color: color.computeLuminance() > 0.5
                  ? Colors.black26
                  : Colors.white24)
          : Text(
              first,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: color.computeLuminance() > 0.5
                    ? Colors.black26
                    : Colors.white24,
              ),
            ),
    );
  }
}
