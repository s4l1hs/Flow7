
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
import 'components/app_header.dart';
import 'components/animated_fade_in.dart';
import 'pages/subscription_page.dart';
import 'pages/program_page.dart';
import 'pages/settings_page.dart';

class MainScreen extends StatefulWidget {
  final String idToken;
  const MainScreen({super.key, required this.idToken});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late final List<Widget> _pages;
  late List<Map<String, dynamic>> _navItems;
  late AnimationController _bounceController;
  late AnimationController _fabPulse;
  late final GlobalKey programPageKey;

  @override
  void initState() {
    super.initState();
    programPageKey = GlobalKey();
    _pages = <Widget>[
      ProgramPage(key: programPageKey, idToken: widget.idToken),
      SubscriptionPage(idToken: widget.idToken),
      const SettingsPage(),
    ];
    _bounceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _fabPulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _fabPulse.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final localizations = AppLocalizations.of(context)!;
    _navItems = [
      {'icon': Icons.calendar_today_rounded, 'tooltip': localizations.programCalendar, 'color': Theme.of(context).colorScheme.tertiary},
      {'icon': Icons.workspace_premium_outlined, 'tooltip': localizations.subscriptions, 'color': Theme.of(context).colorScheme.secondary},
      {'icon': Icons.settings_outlined, 'tooltip': localizations.navSettings, 'color': Colors.grey},
    ];
  }

  void onItemTapped(int index) {
    if (_selectedIndex == index) {
      _bounceController.forward(from: 0);
      return;
    }
    setState(() {
      _selectedIndex = index;
      _bounceController.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBody: true,
      body: Stack(children: [
        Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [theme.colorScheme.primary.withOpacity(0.06), theme.colorScheme.secondary.withOpacity(0.04), theme.scaffoldBackgroundColor])))),
        Positioned(top: -80.h, left: -80.w, child: _ambientBlob(theme.colorScheme.primary.withOpacity(0.08), 260.w)),
        Positioned(bottom: -120.h, right: -80.w, child: _ambientBlob(theme.colorScheme.secondary.withOpacity(0.06), 300.w)),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
            child: Column(
              children: [
                AppHeader(selectedIndex: _selectedIndex),
                SizedBox(height: 18.h),
                Expanded(
                  child: FadeInUp(
                    delay: const Duration(milliseconds: 40),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24.r),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          color: theme.cardColor.withOpacity(0.06),
                          child: IndexedStack(index: _selectedIndex, children: _pages),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 22.w,
          bottom: 120.h,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: ScaleTransition(scale: anim, child: child)),
            child: _selectedIndex == 0
                ? GestureDetector(
                    key: const ValueKey('fab_visible'),
                    onTap: () {
                      _bounceController.forward(from: 0);
                      _openCreatePlan(context);
                    },
                    child: ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut)),
                      child: AnimatedBuilder(
                        animation: _fabPulse,
                        builder: (context, child) {
                          final pulse = 1.0 + (_fabPulse.value * 0.04);
                          return Transform.scale(scale: pulse, child: child);
                        },
                        child: Container(
                          width: 78.r,
                          height: 78.r,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [theme.colorScheme.primary, theme.colorScheme.tertiary]),
                            boxShadow: [BoxShadow(color: theme.colorScheme.primary.withOpacity(0.18), blurRadius: 28.r, offset: Offset(0, 12.h)), BoxShadow(color: Colors.black12, blurRadius: 8.r, offset: Offset(0, 6.h))],
                          ),
                          child: Center(child: Icon(Icons.add, color: Colors.white, size: 34.r)),
                        ),
                      ),
                    ),
                  )
                : SizedBox(key: const ValueKey('fab_hidden'), width: 78.r, height: 78.r),
          ),
        ),
      ]),
      bottomNavigationBar: _buildCustomBottomNav(),
    );
  }

  Widget _ambientBlob(Color color, double size) {
    return Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, Colors.transparent])));
  }

  

  void _openCreatePlan(BuildContext context) {
    (programPageKey.currentState as dynamic)?.showPlanDialog();
  }

  Widget _buildCustomBottomNav() {
    final theme = Theme.of(context);
    final viewPadding = MediaQuery.of(context).viewPadding;
    final bottomPadding = viewPadding.bottom > 0 ? viewPadding.bottom : 12.h;

    return SafeArea(
      bottom: true,
      child: Padding(
        padding: EdgeInsets.only(left: 12.w, right: 12.w, bottom: 6.h),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28.r),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 86.h + bottomPadding,
              padding: EdgeInsets.only(bottom: bottomPadding, top: 8.h),
              decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.04), borderRadius: BorderRadius.circular(28.r)),
              child: Stack(
                children: [
                  const SizedBox.shrink(),
                   Row(
                    children: _navItems.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final itm = entry.value;
                      final isSelected = idx == _selectedIndex;
                      final baseColor = (itm['color'] as Color?) ?? theme.colorScheme.primary;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onItemTapped(idx),
                          child: SizedBox(
                            height: double.infinity,
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                                decoration: BoxDecoration(
                                  color: isSelected ? baseColor.withOpacity(0.06) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Transform.scale(
                                  scale: isSelected ? 1.08 : 1.0,
                                  child: Icon(
                                    itm['icon'] as IconData,
                                    size: isSelected ? 28.sp : 24.sp,
                                    color: isSelected ? baseColor : theme.iconTheme.color!.withOpacity(0.78),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
