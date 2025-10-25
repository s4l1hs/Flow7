// lib/main_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
import 'pages/subscription_page.dart';
import 'pages/program_page.dart';
import 'pages/settings_page.dart';
import 'services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    _pages = <Widget>[
      ProgramPage(idToken: widget.idToken),
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
      {'icon': Icons.calendar_today_rounded, 'tooltip': localizations.programCalendar, 'color': Theme.of(context).colorScheme.primary},
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
        // Luxury multi-layer background
        Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [theme.colorScheme.primary.withOpacity(0.06), theme.colorScheme.secondary.withOpacity(0.04), theme.scaffoldBackgroundColor])))),
        // animated ambient blobs
        Positioned(top: -80.h, left: -80.w, child: _ambientBlob(theme.colorScheme.primary.withOpacity(0.08), 260.w)),
        Positioned(bottom: -120.h, right: -80.w, child: _ambientBlob(theme.colorScheme.secondary.withOpacity(0.06), 300.w)),
        // Content with glass card frame
        SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
            child: Column(
              children: [
                // Top bar: translucent search + date + avatar
                _buildTopBar(context),
                SizedBox(height: 18.h),
                Expanded(
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
              ],
            ),
          ),
        ),
        // FAB with luminous glow and micro animation
        Positioned(
          right: 22.w,
          bottom: 86.h,
          child: ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut)),
            child: AnimatedBuilder(
              animation: _fabPulse,
              builder: (context, child) {
                final pulse = 1.0 + (_fabPulse.value * 0.04);
                return Transform.scale(scale: pulse, child: child);
              },
              child: GestureDetector(
                onTap: () => _openCreatePlan(context),
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
          ),
        ),
      ]),
      bottomNavigationBar: _buildCustomBottomNav(),
    );
  }

  Widget _ambientBlob(Color color, double size) {
    return Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, Colors.transparent])));
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    // date string created on-the-fly where needed (no unused local)
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52.h,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.06), borderRadius: BorderRadius.circular(12.r)),
            child: Row(children: [
              Icon(Icons.search, color: theme.iconTheme.color?.withOpacity(0.7)),
              SizedBox(width: 10.w),
              Expanded(child: Text('Search plans, tags, people...', style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6)))),
              SizedBox(width: 8.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.9), borderRadius: BorderRadius.circular(10.r)),
                child: Text(MaterialLocalizations.of(context).formatShortDate(DateTime.now()), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        ),
        SizedBox(width: 12.w),
        CircleAvatar(radius: 22.r, backgroundColor: Theme.of(context).colorScheme.secondary, child: Icon(Icons.person, color: Colors.white)),
      ],
    );
  }

  void _openCreatePlan(BuildContext context) {
    // delegate to ProgramPage's showPlanDialog via GlobalKey could be used; we simply open dialog to today
    showDialog(context: context, builder: (ctx) => PlanDialog(initialDate: DateTime.now(), onSave: (data) async {
      final api = ApiService();
      try {
        await api.createPlan(widget.idToken, data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.saved), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e'), backgroundColor: Theme.of(context).colorScheme.error));
      }
    }));
  }

  Widget _buildCustomBottomNav() {
    final theme = Theme.of(context);
    final viewPadding = MediaQuery.of(context).viewPadding;
    final bottomPadding = viewPadding.bottom > 0 ? viewPadding.bottom : 12.h;
    final totalWidth = MediaQuery.of(context).size.width - 24.w;
    final itemWidth = totalWidth / _navItems.length;
    final currentColor = (_navItems[_selectedIndex]['color'] as Color?) ?? theme.colorScheme.primary;

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
              child: Stack(children: [
                // highlight pill
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 420),
                  left: 12.w + (_selectedIndex * itemWidth) + (itemWidth - (itemWidth * 0.6)) / 2,
                  top: 6.h,
                  width: itemWidth * 0.6,
                  height: 54.h,
                  child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [currentColor.withOpacity(0.14), currentColor.withOpacity(0.06)]), borderRadius: BorderRadius.circular(14.r))),
                ),
                Row(
                  children: _navItems.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final itm = entry.value;
                    final isSelected = idx == _selectedIndex;
                    final itemColor = isSelected ? (itm['color'] as Color) : theme.iconTheme.color!.withOpacity(0.72);
                    return Expanded(
                      child: InkWell(
                        onTap: () => onItemTapped(idx),
                        child: SizedBox(
                          height: double.infinity,
                          child: Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(itm['icon'] as IconData, size: isSelected ? 28.sp : 24.sp, color: itemColor),
                              SizedBox(height: 4.h),
                              if (isSelected) Container(width: 6.w, height: 6.w, decoration: BoxDecoration(color: itemColor, shape: BoxShape.circle))
                            ]),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}