// lib/main_screen.dart

import 'dart:math' as math;
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
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
  late final List<Widget> _pages; // pages are retained in memory
  late List<Map<String, dynamic>> _navItems;
  late AnimationController _bounceController;
  // key to access ProgramPage state to open the add-dialog from here
  final GlobalKey<ProgramPageState> _programKey = GlobalKey<ProgramPageState>();

  @override
  void initState() {
    super.initState();
    // Keep pages in the order: Program (plans), Subscriptions, Settings
    _pages = <Widget>[
      ProgramPage(key: _programKey, idToken: widget.idToken),
      SubscriptionPage(idToken: widget.idToken),
      const SettingsPage(),
    ];
    _bounceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final localizations = AppLocalizations.of(context)!;
    // Only three icons, no labels: Program (plans), Subscriptions, Settings
    _navItems = [
      {'icon': Icons.event_note_outlined, 'tooltip': localizations.programCalendar, 'color': Colors.indigo},
      {'icon': Icons.subscriptions_outlined, 'tooltip': localizations.subscriptions, 'color': Colors.teal},
      {'icon': Icons.settings_outlined, 'tooltip': localizations.navSettings, 'color': Colors.grey},
    ];
  }

  void onItemTapped(int index) {
    if (_selectedIndex == index) {
      // gentle bounce on re-tap
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
    final screenW = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);

    return Scaffold(
      extendBody: true,
      // Soft layered background for a "sweet & smooth" aesthetic
      body: Stack(
        children: [
          // subtle gradient base
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.9, -0.6),
                end: Alignment(0.9, 0.6),
                colors: [
                  theme.colorScheme.background.withOpacity(1.0),
                  theme.colorScheme.surface.withOpacity(0.98),
                ],
                stops: [0.0, 1.0],
              ),
            ),
          ),

          // two soft radial accents for depth
          Positioned(
            left: -screenW * 0.15,
            top: -120.h,
            child: Container(
              width: 280.w,
              height: 280.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -screenW * 0.10,
            bottom: -100.h,
            child: Container(
              width: 220.w,
              height: 220.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    theme.colorScheme.secondary.withOpacity(0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Page content with smooth cross-fade between pages
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: IndexedStack(
              key: ValueKey<int>(_selectedIndex),
              index: _selectedIndex,
              children: _pages,
            ),
          ),

          // small subtle top-right decorative gradient blob preserved for style
          Positioned(
            right: -min(60.w, screenW * 0.08),
            top: -min(60.h, MediaQuery.of(context).size.height * 0.08),
            child: Transform.rotate(
              angle: -0.5,
              child: Container(
                width: min(200.w, screenW * 0.45),
                height: min(200.w, screenW * 0.45),
                decoration: BoxDecoration(
                  gradient: RadialGradient(colors: [theme.colorScheme.primary.withOpacity(0.10), Colors.transparent]),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),

      // Floating + button with softened shadow and subtle scale pulse
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Visibility(
        visible: _selectedIndex == 0,
        child: Padding(
          padding: EdgeInsets.only(bottom: 18.h, right: 16.w),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 1.06).animate(
              CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
            ),
            child: GestureDetector(
              onTap: () {
                final state = _programKey.currentState;
                if (state != null) state.showPlanDialog();
                _bounceController.forward(from: 0);
              },
              child: Container(
                width: 66.r,
                height: 66.r,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withOpacity(0.92),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.18),
                      blurRadius: 24.r,
                      offset: Offset(0, 10.h),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 6.r,
                      offset: Offset(0, 4.h),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(66.r),
                    onTap: () {
                      final state = _programKey.currentState;
                      if (state != null) state.showPlanDialog();
                      _bounceController.forward(from: 0);
                    },
                    child: Center(
                      child: Icon(Icons.add, color: Colors.white, size: 32.r),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),

      bottomNavigationBar: _buildCustomBottomNav(),
    );
  }

  Widget _buildCustomBottomNav() {
    final theme = Theme.of(context);
    final viewPadding = MediaQuery.of(context).viewPadding;
    final double bottomPadding = viewPadding.bottom > 0 ? viewPadding.bottom : 12.h;

    Color getSelectedColor(int index) {
      final c = _navItems[index]['color'];
      if (c is Color) return c;
      return theme.colorScheme.primary;
    }

    final currentColor = getSelectedColor(_selectedIndex);

    return SafeArea(
      bottom: true,
      child: Padding(
        padding: EdgeInsets.only(left: 12.w, right: 12.w, bottom: 6.h),
        child: LayoutBuilder(builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final itemCount = _navItems.length; // should be 3 now
          final itemWidth = (totalWidth) / itemCount;
          final leftPaddingForHighlight = 6.w;

          double highlightLeft = leftPaddingForHighlight + (_selectedIndex * itemWidth);
          highlightLeft = highlightLeft.clamp(0.0, (totalWidth - itemWidth).clamp(0.0, totalWidth));

          final double highlightWidth = (itemWidth * 0.58).clamp(56.0, (itemWidth - 12.0).clamp(56.0, totalWidth));

          return ClipRRect(
            borderRadius: BorderRadius.circular(24.r),
            clipBehavior: Clip.hardEdge,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
              child: Container(
                height: 96.h + bottomPadding,
                padding: EdgeInsets.only(bottom: bottomPadding, top: 8.h),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(24.r),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 18.r, offset: Offset(0, 6.h))],
                  border: Border.all(color: theme.colorScheme.surface.withOpacity(0.06)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // floating highlighted pill behind selected icon
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      left: math.max(0.0, (highlightLeft + (itemWidth - highlightWidth) / 2).clamp(0.0, totalWidth - highlightWidth)),
                      top: 4.h,
                      width: highlightWidth,
                      height: 58.h,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeOutCubic,
                          width: highlightWidth,
                          height: 52.h,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [currentColor.withOpacity(0.16), currentColor.withOpacity(0.06)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14.r),
                            boxShadow: [BoxShadow(color: currentColor.withOpacity(0.10), blurRadius: 20.r, offset: Offset(0, 8.h))],
                            border: Border.all(color: currentColor.withOpacity(0.08)),
                          ),
                        ),
                      ),
                    ),

                    Row(
                      children: _navItems.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        final isSelected = _selectedIndex == index;
                        final Color itemColor = isSelected ? getSelectedColor(index) : theme.iconTheme.color!.withOpacity(0.72);

                        return Expanded(
                          child: GestureDetector(
                            onTap: () => onItemTapped(index),
                            behavior: HitTestBehavior.opaque,
                            child: SizedBox(
                              height: double.infinity,
                              child: Center(
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: isSelected ? 1.08 : 1.0, end: isSelected ? 1.08 : 1.0),
                                  duration: const Duration(milliseconds: 360),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, scale, child) {
                                    return Transform.scale(
                                      scale: scale,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 320),
                                        curve: Curves.easeOut,
                                        padding: EdgeInsets.all(isSelected ? 6.w : 8.w),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected ? itemColor.withOpacity(0.04) : Colors.transparent,
                                        ),
                                        child: Icon(
                                          item['icon'] as IconData,
                                          size: isSelected ? 30.sp : 26.sp,
                                          color: itemColor,
                                          semanticLabel: (item['tooltip'] as String?) ?? '',
                                        ),
                                      ),
                                    );
                                  },
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
          );
        }),
      ),
    );
  }
}