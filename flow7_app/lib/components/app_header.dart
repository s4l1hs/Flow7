import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
// firebase auth import removed (not used here)
import '../l10n/app_localizations.dart';
import 'animated_fade_in.dart';

class AppHeader extends StatelessWidget {
  final int selectedIndex;
  const AppHeader({super.key, this.selectedIndex = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final subtitle = selectedIndex == 0 ? loc.planAndSuccess : selectedIndex == 1 ? loc.subtitleSubscription : loc.subtitleSettings;

    return FadeInUp(
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 64.h,
              padding: EdgeInsets.only(left: 10.w, right: 14.w),
              decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.04), borderRadius: BorderRadius.circular(14.r), border: Border.all(color: theme.dividerColor.withOpacity(0.04))),
              child: Row(children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [theme.colorScheme.primary.withOpacity(0.95), theme.colorScheme.tertiary.withOpacity(0.9)]), boxShadow: [BoxShadow(color: theme.colorScheme.primary.withOpacity(0.12), blurRadius: 10.r, offset: Offset(0, 6.h))]),
                  child: Center(child: Icon(Icons.local_play, color: Colors.white, size: 18.sp)),
                ),
                SizedBox(width: 8.w),
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Flow7', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  SizedBox(height: 4.h),
                  Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8))),
                ])),
              ]),
            ),
          ),
          SizedBox(width: 12.w),
          Container(padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h), decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.95), borderRadius: BorderRadius.circular(10.r)), child: Text(MaterialLocalizations.of(context).formatShortDate(DateTime.now()), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}
