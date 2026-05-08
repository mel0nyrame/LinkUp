import 'package:flutter/material.dart';

/// 轻量卡片 — 半透明白色 + 微边框。
/// 不在每张卡片上使用 LiquidGlass（太重），真液态玻璃效果仅用于 Hero 状态卡和底部导航栏。
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 16,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: const Color(0x33FFFFFF),
          width: 0.5,
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(padding: margin, child: card),
      );
    }

    return Padding(padding: margin, child: card);
  }
}
