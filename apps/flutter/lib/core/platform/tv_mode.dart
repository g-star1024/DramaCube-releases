import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV 模式检测与工具。
///
/// 通过 UiModeManager 判断是否 Android TV（feature: android.software.leanback）。
/// Flutter 侧用 MediaQuery 宽度 + 平台组合判断，main.dart 启动时注入。
class TVMode {
  TVMode._();

  static bool _isTV = false;
  static bool get isTV => _isTV;

  /// 启动时调用（main.dart），传入平台检测结果。
  static void init({required bool isTV}) {
    _isTV = isTV;
    if (kDebugMode) {
      // ignore: avoid_print
      print('[TVMode] isTV=$isTV');
    }
  }

  /// 卡片宽度（TV 更大）。
  static double cardExtent(BuildContext context) {
    if (isTV) return 200;
    return MediaQuery.of(context).size.width < 720 ? 120 : 160;
  }

  /// 字体缩放（TV 字体更大，10 英尺体验）。
  static double get textScale => isTV ? 1.3 : 1.0;
}

/// TV 焦点包装器：自动焦点请求 + 焦点高亮（边框 + 缩放）。
///
/// 用法：包在卡片/按钮外面，D-pad 导航时自动高亮。
class TVFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final bool autofocus;

  const TVFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.autofocus = false,
  });

  @override
  State<TVFocusable> createState() => _TVFocusableState();
}

class _TVFocusableState extends State<TVFocusable> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!TVMode.isTV) {
      // 非 TV：直接返回子组件 + 点击
      return GestureDetector(onTap: widget.onSelect, child: widget.child);
    }
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onSelect?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.identity()..scaleByDouble(_focused ? 1.05 : 1.0, 1.05, 1.0, 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          border: _focused
              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3)
              : Border.all(color: Colors.transparent, width: 3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: widget.child,
      ),
    );
  }
}

/// TV 快捷键包装器：全局 D-pad 导航增强。
///
/// 包在 Scaffold 外面，处理遥控器特殊按键。
class TVShortcutHandler extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onMenu;

  const TVShortcutHandler({
    super.key,
    required this.child,
    this.onBack,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    if (!TVMode.isTV) return child;
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.goBack): const _BackIntent(),
        LogicalKeySet(LogicalKeyboardKey.contextMenu): const _MenuIntent(),
      },
      child: Actions(
        actions: {
          _BackIntent: CallbackAction<_BackIntent>(onInvoke: (_) {
            onBack?.call();
            return null;
          }),
          _MenuIntent: CallbackAction<_MenuIntent>(onInvoke: (_) {
            onMenu?.call();
            return null;
          }),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

class _MenuIntent extends Intent {
  const _MenuIntent();
}
