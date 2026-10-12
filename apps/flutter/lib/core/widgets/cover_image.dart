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

    // 豆瓣图防盗链：带 Referer 请求（对齐 macOS 版 image-proxy 方案）。
    Map<String, String>? headers = httpHeaders;
    if (headers == null && Uri.tryParse(url!)?.host.contains('doubanio') == true) {
      headers = const {
        'Referer': 'https://m.douban.com/',
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15',
      };
    }

    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      httpHeaders: headers,
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
