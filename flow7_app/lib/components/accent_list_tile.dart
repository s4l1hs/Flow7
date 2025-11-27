import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'animated_fade_in.dart';

class AccentListTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const AccentListTile({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = ListTile(
      onTap: onTap,
      leading: CircleAvatar(backgroundColor: theme.colorScheme.primary.withOpacity(0.12), child: Icon(icon, color: theme.colorScheme.tertiary)),
      title: Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle!, style: theme.textTheme.bodySmall) : null,
      trailing: trailing ?? Icon(Icons.chevron_right, color: Colors.white70),
    );

    return FadeInUp(child: PressableScale(onTap: onTap, child: tile));
  }
}
