import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../providers/user_provider.dart';

class SubscriptionPage extends StatefulWidget {
  final String idToken;
  const SubscriptionPage({super.key, required this.idToken});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  bool _isProcessing = false;

  Future<void> _simulatePurchase(String level) async {
    final localizations = AppLocalizations.of(context)!;
    final apiService = ApiService();

    setState(() => _isProcessing = true);
    try {
      await apiService.updateSubscription(widget.idToken, level, 30);
      if (mounted) {
        Provider.of<UserProvider>(context, listen: false).loadProfile(widget.idToken);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.purchaseSuccess), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${localizations.purchaseError}: ${e.toString()}"), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final userProvider = Provider.of<UserProvider>(context);
    final currentLevel = userProvider.profile?.subscriptionLevel ?? 'free';

    // Plan definitions simplified per request: only week limits and support perks
    final List<Map<String, dynamic>> plans = [
      {
        'level': 'free',
        'title': localizations.planFree,
        'color': Colors.grey.shade700,
        'price': localizations.free,
        'limitWeeks': 2,
        'perks': <String>[],
      },
      {
        'level': 'pro',
        'title': localizations.planPro,
        'color': theme.colorScheme.primary,
        'price': '\$4.99 / ${localizations.month}',
        'limitWeeks': 4,
        'perks': <String>[localizations.basicSupport],
      },
      {
        'level': 'ultra',
        'title': localizations.planUltra,
        'color': theme.colorScheme.secondary,
        'price': '\$9.99 / ${localizations.month}',
        'limitWeeks': 8,
        'perks': <String>[localizations.prioritySupport],
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      // SafeArea removed and top padding minimized so content sits higher
      body: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lift header a bit with translate so it's visually higher
            Transform.translate(
              offset: Offset(0, -10.h),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [theme.colorScheme.primary.withOpacity(0.16), theme.colorScheme.secondary.withOpacity(0.05)],
                        ),
                        borderRadius: BorderRadius.circular(14.r),
                        boxShadow: [
                          BoxShadow(color: theme.brightness == Brightness.dark ? Colors.black38 : Colors.black12, blurRadius: 12.r, offset: Offset(0,6.h))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(localizations.chooseYourPlan, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800, color: Colors.white)),
                          SizedBox(height: 4.h),
                          Text(localizations.subscriptionNote, style: TextStyle(fontSize: 12.sp, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Container(
                    width: 52.w,
                    height: 52.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [theme.colorScheme.primary, theme.colorScheme.secondary]),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8.r, offset: Offset(0,6.h))],
                    ),
                    child: Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 28.sp),
                  )
                ],
              ),
            ),
            SizedBox(height: 10.h),

            // reduced horizontal cards area height to avoid vertical overflow
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                itemCount: plans.length,
                physics: BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  final plan = plans[index];
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w), // küçük yatay boşluk her kart arasında
                    child: _buildSubscriptionCard(theme, localizations, plan, currentLevel),
                  );
                },
              ),
            ),
            SizedBox(height: 12.h),
            Center(
              child: Text(localizations.subscriptionNote, style: TextStyle(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7) ?? Colors.grey.shade400, fontSize: 12.sp), textAlign: TextAlign.center),
            ),
            SizedBox(height: 6.h),
            if (_isProcessing) Center(child: Padding(padding: EdgeInsets.only(top: 6.h), child: CircularProgressIndicator()))
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard(ThemeData theme, AppLocalizations localizations, Map<String, dynamic> plan, String currentLevel) {
    final bool isCurrent = plan['level'] == currentLevel;
    final Color cardColor = plan['color'] as Color;
    final String planLevel = plan['level'] as String;
    final bool isFree = planLevel == 'free';

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 420),
      tween: Tween(begin: 0.98, end: isCurrent ? 1.03 : 1.0),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: () {
          if (!isCurrent) _simulatePurchase(planLevel);
        },
        child: Builder(builder: (context) {
            // Reduced card height/width to prevent bottom overflow on small viewports
            final double screenW = MediaQuery.of(context).size.width;
            final double screenH = MediaQuery.of(context).size.height;
            final double cardHeight = math.min(screenH * 0.30, screenH * 0.65);
            final double cardWidth = math.min(screenW * 0.72, 340.w);
  
            // Capabilities per plan (icons + localized labels)
            final List<Map<String, dynamic>> capabilities = planLevel == 'free'
                ? [
                    {'icon': Icons.view_week, 'label': localizations.view2Weeks},
                    {'icon': Icons.notifications_none, 'label': localizations.basicReminders},
                    {'icon': Icons.sync_disabled, 'label': localizations.noSupport},
                  ]
                : planLevel == 'pro'
                    ? [
                        {'icon': Icons.view_week, 'label': localizations.view4Weeks},
                        {'icon': Icons.notifications_active, 'label': localizations.advancedReminders},
                        {'icon': Icons.headset_mic, 'label': localizations.basicSupport},
                      ]
                    : [
                        {'icon': Icons.calendar_view_month, 'label': localizations.view8Weeks},
                        {'icon': Icons.notifications_active, 'label': localizations.advancedRemindersAndSnooze},
                        {'icon': Icons.headset, 'label': localizations.prioritySupport},
                      ];

            // stronger visual for pro / ultra
            final Gradient cardGradient = planLevel == 'pro'
                ? LinearGradient(colors: [cardColor.withOpacity(0.96), cardColor.withOpacity(0.68)])
                : planLevel == 'ultra'
                    ? LinearGradient(colors: [cardColor.withOpacity(1.0), cardColor.withOpacity(0.78)])
                    : LinearGradient(colors: [cardColor.withOpacity(0.22), cardColor.withOpacity(0.08)]);
            final List<BoxShadow> cardShadow = planLevel == 'pro'
                ? [BoxShadow(color: cardColor.withOpacity(0.22), blurRadius: 22.r, offset: Offset(0,12.h))]
                : planLevel == 'ultra'
                    ? [BoxShadow(color: cardColor.withOpacity(0.28), blurRadius: 28.r, offset: Offset(0,14.h))]
                    : [BoxShadow(color: theme.brightness == Brightness.dark ? Colors.black38 : Colors.black12, blurRadius: 16.r, offset: Offset(0,10.h))];

            return SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: Container(
              padding: EdgeInsets.all(14.w),
              decoration: BoxDecoration(
                gradient: isCurrent ? cardGradient : LinearGradient(colors: [theme.brightness == Brightness.dark ? Colors.white10 : Colors.white.withOpacity(0.02), theme.brightness == Brightness.dark ? Colors.white12 : Colors.white.withOpacity(0.03)]),
                borderRadius: BorderRadius.circular(16.r),
                border: isCurrent ? Border.all(color: cardColor.withOpacity(0.14), width: 1.4.w) : Border.all(color: Colors.transparent),
                boxShadow: cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge row: small ribbon for pro/ultra
                  Row(
                    children: [
                      if (planLevel == 'pro' || planLevel == 'ultra')
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [Colors.white24, Colors.white10]),
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Row(
                            children: [
                              Icon(planLevel == 'pro' ? Icons.thumb_up : Icons.star, size: 12.sp, color: Colors.white),
                              SizedBox(width: 6.w),
                              Text(
                                planLevel == 'pro' ? (localizations.mostPopular) : (localizations.bestValue),
                                style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      Spacer(),
                      // Price pill (emphasize for pro/ultra)
                      if (!isFree)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                          decoration: BoxDecoration(
                            color: planLevel == 'pro' ? Colors.white : Colors.white,
                            borderRadius: BorderRadius.circular(12.r),
                            boxShadow: planLevel == 'pro'
                                ? [BoxShadow(color: Colors.black12, blurRadius: 8.r, offset: Offset(0,4.h))]
                                : [BoxShadow(color: Colors.black26, blurRadius: 10.r, offset: Offset(0,6.h))],
                          ),
                          child: Text(plan['price'] as String, style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, fontSize: 12.sp)),
                        ),
                    ],
                  ),

                  SizedBox(height: 8.h),

                  // Title row: left aligned title, small subtitle to make pro/ultra inviting
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(plan['title'] as String, style: TextStyle(color: isCurrent || planLevel != 'free' ? Colors.white : Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),

                  // thin separator
                  Container(height: 3.h, width: 56.w, decoration: BoxDecoration(gradient: LinearGradient(colors: [cardColor.withOpacity(0.95), cardColor.withOpacity(0.55)]), borderRadius: BorderRadius.circular(12.r))),
                  SizedBox(height: 8.h),

                  // Avantajlar: alt alta liste (ikon + text) with centered alignment
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: capabilities.map<Widget>((c) {
                          return Padding(
                            padding: EdgeInsets.only(bottom: 10.h),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center, // align text with icon center
                              children: [
                                Container(
                                  width: 36.w,
                                  height: 36.w,
                                  decoration: BoxDecoration(
                                    color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.black12,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(child: Icon(c['icon'] as IconData, color: cardColor, size: 18.sp)),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Text(
                                    c['label'] as String,
                                    style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 13.sp, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  SizedBox(height: 6.h),

                  // CTA — more prominent for pro/ultra
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isCurrent || _isProcessing ? null : () => _simulatePurchase(planLevel),
                      style: ElevatedButton.styleFrom(
                      backgroundColor: ['ultra', 'pro'].contains(planLevel)
                          ? cardColor
                          : (isCurrent
                              ? (theme.brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade300)
                              : cardColor),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        elevation: planLevel == 'ultra' ? 10 : (planLevel == 'pro' ? 6 : 2),
                      ),
                      child: Text(
                        isCurrent ? localizations.active : (isFree ? localizations.freeTrial : localizations.upgrade),
                        style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800, color: planLevel == 'ultra' ? Colors.white : Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

