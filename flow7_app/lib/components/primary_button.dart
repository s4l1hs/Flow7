import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'animated_fade_in.dart';

class PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const PrimaryButton({super.key, required this.child, this.onPressed, this.padding = const EdgeInsets.symmetric(vertical: 12)});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final btn = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.secondary,
        foregroundColor: theme.colorScheme.onPrimary,
        padding: padding,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
        elevation: 6,
      ),
      child: child,
    );

    return FadeInUp(child: PressableScale(onTap: onPressed, child: btn));
  }
}
