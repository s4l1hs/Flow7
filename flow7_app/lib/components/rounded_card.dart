import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'animated_fade_in.dart';

class RoundedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? color;
  final double elevation;
  final VoidCallback? onTap;

  const RoundedCard({super.key, required this.child, this.padding, this.borderRadius = 16.0, this.color, this.elevation = 8.0, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = Card(
      elevation: elevation,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius.r)),
      color: color ?? theme.colorScheme.surface.withOpacity(0.06),
      child: Padding(padding: padding ?? EdgeInsets.all(12.w), child: child),
    );

    final content = onTap != null
        ? PressableScale(onTap: onTap, child: card)
        : card;

    return FadeInUp(child: content);
  }
}
