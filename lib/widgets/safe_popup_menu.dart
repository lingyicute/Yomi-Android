import 'package:flutter/material.dart';

/// 安全的弹出菜单按钮，确保在任何情况下都能访问有效的Navigator上下文
/// 
/// 这个组件解决了"Null check operator used on a null value"错误，
/// 该错误发生在Navigator.of调用找不到有效上下文的情况
class SafePopupMenu<T> extends StatelessWidget {
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final Widget? child;
  final String? tooltip;
  final Icon? icon;
  final Color? iconColor;
  final EdgeInsetsGeometry? padding;
  final double? offset;
  final PopupMenuPosition? position;
  final bool useRootNavigator;
  final BoxConstraints? constraints;
  final ShapeBorder? shape;
  final AnimationStyle? popUpAnimationStyle;
  final bool? enabled;

  const SafePopupMenu({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.child,
    this.tooltip,
    this.icon,
    this.iconColor,
    this.padding,
    this.offset,
    this.position,
    this.useRootNavigator = true,
    this.constraints,
    this.shape,
    this.popUpAnimationStyle,
    this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        // 使用Builder确保我们在widget树中有一个有效的context
        return PopupMenuButton<T>(
          itemBuilder: itemBuilder,
          onSelected: onSelected,
          tooltip: tooltip,
          icon: icon,
          iconColor: iconColor,
          padding: padding ?? EdgeInsets.zero,
          offset: offset != null ? Offset(0, offset!) : const Offset(0, 0),
          position: position,
          useRootNavigator: useRootNavigator,
          constraints: constraints,
          shape: shape,
          popUpAnimationStyle: popUpAnimationStyle,
          enabled: enabled ?? true,
          child: child,
        );
      },
    );
  }
} 