import 'package:flutter/material.dart';

import 'tv_focus.dart';
import 'tv_theme.dart';

/// TV 大格键盘 —— 搜索页输入器（A-Z / 0-9 / 删除 / 清空）。
///
/// 5 列大格（≥72dp 触摸目标），方向键 + OK 输入。
class TvKeyboard extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final String initial;

  const TvKeyboard({super.key, required this.onChanged, this.initial = ''});

  @override
  State<TvKeyboard> createState() => _TvKeyboardState();
}

class _TvKeyboardState extends State<TvKeyboard> {
  late String _text = widget.initial;

  static const _chars = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  ];

  void _input(String c) {
    if (_text.length >= 30) return;
    setState(() => _text += c);
    widget.onChanged(_text);
  }

  void _backspace() {
    if (_text.isEmpty) return;
    setState(() => _text = _text.substring(0, _text.length - 1));
    widget.onChanged(_text);
  }

  void _clear() {
    setState(() => _text = '');
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TvSafeArea.left),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 输入回显
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: TvColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: TvColors.surfaceHi),
            ),
            child: Text(
              _text.isEmpty ? '输入片名搜索…' : _text,
              style: TextStyle(
                color: _text.isEmpty ? TvColors.muted : TvColors.onSurface,
                fontSize: TvText.body,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 大格键盘（5 列）
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
            ),
            itemCount: _chars.length + 2, // + 删除 + 清空
            itemBuilder: (context, i) {
              if (i == _chars.length) {
                return _KeyCell(
                  label: '删除',
                  icon: Icons.backspace_outlined,
                  onPressed: _backspace,
                );
              }
              if (i == _chars.length + 1) {
                return _KeyCell(
                  label: '清空',
                  icon: Icons.clear,
                  onPressed: _clear,
                );
              }
              final c = _chars[i];
              return _KeyCell(label: c, onPressed: () => _input(c));
            },
          ),
        ],
      ),
    );
  }
}

class _KeyCell extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;

  const _KeyCell({required this.label, this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: TvColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: icon != null
            ? Icon(icon, color: TvColors.onSurface, size: 26)
            : Text(
                label,
                style: const TextStyle(
                  color: TvColors.onSurface,
                  fontSize: TvText.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
