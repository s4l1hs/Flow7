import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';
import 'dart:ui';
import 'dart:math' as math;

class ProgramPage extends StatefulWidget {
  final String idToken; 
  const ProgramPage({super.key, required this.idToken});

  @override
  State<ProgramPage> createState() => ProgramPageState();
}

class ProgramPageState extends State<ProgramPage> {
  final ApiService _apiService = ApiService();
  late PageController _pageController;
  DateTime _baseWeekStart = _getStartOfWeek(DateTime.now());
  DateTime _currentWeekStart;
  DateTime? _selectedDay;
  int _weekLimit = 2;
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, List<Map<String, dynamic>>> _groupedPlans = {};

  ProgramPageState() : _currentWeekStart = _getStartOfWeek(DateTime.now());

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _pageController = PageController(initialPage: 0);
    _selectedDay = DateTime(today.year, today.month, today.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPlansForWeek(_currentWeekStart));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }


  static DateTime _getStartOfWeek(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  DateTime _getDateForPage(int pageIndex) {
    return _baseWeekStart.add(Duration(days: pageIndex * 7));
  }

  void setSubscriptionTier(String tier) {
    final t = tier.toLowerCase();
    final newLimit = (t == 'pro') ? 4 : (t == 'ultra' ? 8 : 2);
    if (newLimit == _weekLimit) return;
    setState(() {
      _weekLimit = newLimit;
      final currentPage = ((_currentWeekStart.difference(_baseWeekStart).inDays ~/ 7).clamp(0, _weekLimit - 1)).toInt();
      _pageController.dispose();
      _pageController = PageController(initialPage: currentPage);
      _currentWeekStart = _getDateForPage(currentPage);
      _selectedDay = _getDateForPage(currentPage);
    });
  }

  void updateSubscription(String tier) => setSubscriptionTier(tier);

  void _groupAndSortPlans(List<Map<String, dynamic>> plans, {bool merge = false}) 
  {
    final Map<String, List<Map<String, dynamic>>> newGrouped = {};

      final newlyGrouped = groupBy(plans, (plan) {
        final rawDate = plan['date'];
        if (rawDate is String && rawDate.length >= 10) {
          return rawDate.substring(0, 10);
        } else if (rawDate is DateTime) {
          return DateFormat('yyyy-MM-dd').format(rawDate);
        } else {
          return rawDate.toString().substring(0, 10);
        }
      });

      if (merge) {
          newGrouped.addAll(_groupedPlans);

          newlyGrouped.forEach((dateKey, plansList) {
              newGrouped[dateKey] = plansList;
          });
      } else {
          newGrouped.addAll(newlyGrouped);
      }

      newGrouped.forEach((date, planList) {
        planList.sort((a, b) {
          final startTimeA = a['start_time'] as String? ?? '00:00';
          final startTimeB = b['start_time'] as String? ?? '00:00';
          return startTimeA.compareTo(startTimeB);
        });
      });

      _groupedPlans = newGrouped;
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }


  Future<void> _fetchPlansForWeek(DateTime weekStart, {bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final startDate = weekStart;
      final endDate = weekStart.add(const Duration(days: 6));
      final plans = await _apiService.getUserPlans(widget.idToken, startDate, endDate);
      
      if (mounted) {
        setState(() {
          _groupAndSortPlans(plans, merge: true);
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message; 
          _groupedPlans = {};
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AppLocalizations.of(context)!.errorOccurred;
          _groupedPlans = {};
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleApiResponse(Future<dynamic> apiCall) async {
    try {
      final result = await apiCall;
      DateTime? affectedDate;
      if (result is Map && result['date'] != null) {
        try {
          affectedDate = DateTime.parse(result['date'].toString());
        } catch (_) {
          affectedDate = null;
        }
      }

      if (affectedDate != null) {
        final affectedWeekStart = _getStartOfWeek(affectedDate);
        final currentWeekStart = _currentWeekStart;
        final minStart = currentWeekStart.isBefore(affectedWeekStart) ? currentWeekStart : affectedWeekStart;
        final maxStart = currentWeekStart.isAfter(affectedWeekStart) ? currentWeekStart : affectedWeekStart;
        final rangeStart = minStart;
        final rangeEnd = maxStart.add(const Duration(days: 6));

        try {
          final plans = await _apiService.getUserPlans(widget.idToken, rangeStart, rangeEnd);
          if (mounted) {
            setState(() {
              _groupAndSortPlans(plans, merge: true);
              _isLoading = false;
              _errorMessage = null;
            });
          }
        } catch (e) {
          await _fetchPlansForWeek(_currentWeekStart, showLoading: false);
        }
      } else {
        await _fetchPlansForWeek(_currentWeekStart, showLoading: false);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.errorOccurred),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  void _insertOrUpdatePlan(Map<String, dynamic> plan) {
    final dateKey = plan['date'].toString().substring(0, 10);
    final keys = _groupedPlans.keys.toList();
    for (final k in keys) {
      _groupedPlans[k]?.removeWhere((p) => p['id'] == plan['id']);
      if (_groupedPlans[k]?.isEmpty ?? false) _groupedPlans.remove(k);
    }

    final list = _groupedPlans[dateKey] ?? <Map<String, dynamic>>[];
    list.add(Map<String, dynamic>.from(plan));
    list.sort((a, b) {
      final aStart = a['start_time'] as String? ?? '00:00';
      final bStart = b['start_time'] as String? ?? '00:00';
      return aStart.compareTo(bStart);
    });
    _groupedPlans[dateKey] = list;
    if (mounted) setState(() {});
  }

  void _removePlanById(String id) {
    bool changed = false;
    final keys = _groupedPlans.keys.toList();
    for (final k in keys) {
      final before = _groupedPlans[k]?.length ?? 0;
      _groupedPlans[k]?.removeWhere((p) => p['id'] == id);
      final after = _groupedPlans[k]?.length ?? 0;
      if (after == 0) _groupedPlans.remove(k);
      if (after != before) changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  void _onDeletePlan(String planId) async {
    Map<String, dynamic>? backup;
    for (final list in _groupedPlans.values) {
      for (final p in list) {
        if (p['id'] == planId) {
          backup = Map<String, dynamic>.from(p);
          break;
        }
      }
      if (backup != null) break;
    }

    _removePlanById(planId);

    try {
      await _apiService.deletePlan(widget.idToken, planId);
      await _fetchPlansForWeek(_currentWeekStart, showLoading: false);
    } catch (e) {
      if (backup != null) _insertOrUpdatePlan(backup);
      if (!mounted) return;
      final err = e is ApiException ? e.message : AppLocalizations.of(context)!.errorOccurred;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  void _onCreatePlan(Map<String, dynamic> data) {
    _handleApiResponse(_apiService.createPlan(widget.idToken, data));
  }

  void _onUpdatePlan(String planId, Map<String, dynamic> data) {
    _handleApiResponse(_apiService.updatePlan(widget.idToken, planId, data));
  }
  
  void showPlanDialog({Map<String, dynamic>? plan, DateTime? forDate}) {
    final isEditing = plan != null;
    DateTime date;
    if (isEditing) {
      final parsed = DateTime.parse(plan['date'].toString());
      date = DateTime(parsed.year, parsed.month, parsed.day);
    } else {
      final s = forDate ?? _selectedDay ?? DateTime.now();
      date = DateTime(s.year, s.month, s.day);
    }

    showDialog(context: context, builder: (context) {
      return PlanDialog(initialDate: date, plan: plan, onSave: (data) {
        if (isEditing) _onUpdatePlan(plan['id'].toString(), data); else _onCreatePlan(data);
      });
    });
  }

  void _showDeleteConfirmation(String planId) {
    final loc = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.delete),
        content: Text(loc.deleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _onDeletePlan(planId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(loc.delete),
          ),
        ],
      ),
    );
  }
  

  @override
  Widget build(BuildContext context) {
     final loc = AppLocalizations.of(context)!;
    final double dayPickerHeight = math.min(132.h, MediaQuery.of(context).size.height * 0.16);

    return Scaffold(
      appBar: AppBar(
        title: _buildAnimatedTitle(loc),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: loc.today,
            onPressed: () {
              _pageController.animateToPage(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        ],
      ),
      body: SafeArea(child: Column(children: [
        Container(height: dayPickerHeight, padding: EdgeInsets.symmetric(vertical: 6.h), child: PageView.builder(
          controller: _pageController,
          itemCount: _weekLimit,
          onPageChanged: (pageIndex) {
            final newWeekStart = _getDateForPage(pageIndex);
            setState(() {
              _currentWeekStart = newWeekStart;
              if (_selectedDay == null || _selectedDay!.isBefore(newWeekStart) || _selectedDay!.isAfter(newWeekStart.add(const Duration(days: 6)))) {
                _selectedDay = newWeekStart;
              }
            });
            _fetchPlansForWeek(newWeekStart);
          },
          itemBuilder: (context, pageIndex) {
            final weekStart = _getDateForPage(pageIndex);
            return _buildWeekView(weekStart);
          },
        )),
        const Divider(height: 1),
        Expanded(child: _buildPlanList())
      ])),
    );
  }

  Widget _buildWeekView(DateTime weekStart) {
    final locale = Localizations.localeOf(context).toString();
    final dfDay = DateFormat.E(locale);
    final dfNum = DateFormat.d(locale);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(children: List.generate(7, (index) {
        final day = weekStart.add(Duration(days: index));
        final normalized = DateTime(day.year, day.month, day.day);
        final isToday = _isSameDate(normalized, DateTime.now());
        final isSelected = _selectedDay != null && _isSameDate(normalized, _selectedDay!);
        final dateKey = DateFormat('yyyy-MM-dd').format(normalized);
        final hasPlans = _groupedPlans[dateKey]?.isNotEmpty ?? false;

        return Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 6.w), child: GestureDetector(
          onTap: () => setState(() => _selectedDay = normalized),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            padding: EdgeInsets.symmetric(vertical: 10.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.r),
              gradient: isSelected ? LinearGradient(colors: [Theme.of(context).colorScheme.primary.withOpacity(0.18), Theme.of(context).colorScheme.tertiary.withOpacity(0.06)]) : null,
              border: isSelected ? Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.12)) : Border.all(color: Colors.transparent),
              boxShadow: isSelected ? [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.06), blurRadius: 18.r, offset: Offset(0,8.h))] : null,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: 18.h,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      dfDay.format(normalized),
                      style: TextStyle(fontSize: isArabic ? 24.sp : 32.sp, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600, color: isSelected ? Theme.of(context).colorScheme.tertiary : null),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 6.h),
              Container(
                width: 46.r,
                height: 46.r,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isSelected
                      ? LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.tertiary])
                      : (isToday ? LinearGradient(colors: [Colors.grey.shade700, Colors.grey.shade600]) : null),
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(dfNum.format(normalized), style: TextStyle(color: (isSelected || isToday) ? Colors.white : null, fontWeight: FontWeight.w700)),
                ),
              ),
              SizedBox(height: 6.h),
              if (hasPlans) Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary, shape: BoxShape.circle))
            ]),
          ),
        )));
      })),
    );
  }
  
  Widget _buildPlanList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error))));
    final key = _selectedDay != null ? DateFormat('yyyy-MM-dd').format(_selectedDay!) : null;
    final plansForDay = (key != null ? _groupedPlans[key] : null) ?? [];
    if (plansForDay.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 110.r, height: 110.r, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary.withOpacity(0.12), Theme.of(context).colorScheme.secondary.withOpacity(0.06)]), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 18.r, offset: Offset(0,8.h))]), child: Icon(Icons.event_note_outlined, size: 44.r, color: Theme.of(context).colorScheme.primary)),
        SizedBox(height: 14.h),
        Text(AppLocalizations.of(context)?.noPlansHere ?? "No plans for this day.", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 8.h),
        Text(AppLocalizations.of(context)?.tapToAddPlan ?? "Tap + to add a plan", style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color), textAlign: TextAlign.center),
      ]));
    }

    return ListView.separated(padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w), itemCount: plansForDay.length, separatorBuilder: (_, __) => SizedBox(height: 12.h), itemBuilder: (context, index) {
      final plan = plansForDay[index];
      final start = (plan['start_time'] as String?) ?? '';
      final end = (plan['end_time'] as String?) ?? '';
      final title = (plan['title'] as String?) ?? '';
      final desc = (plan['description'] ?? '').toString();
      final color = Theme.of(context).colorScheme.primary;

      return GestureDetector(
        onTap: () => showPlanDialog(plan: plan),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 72.w, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(start, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700)), if (end.isNotEmpty) Text(end, style: TextStyle(fontSize: 11.sp)), SizedBox(height: 6.h)])),
          Container(width: 28.w, alignment: Alignment.topCenter, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [Container(width: 3.w, height: 12.h, color: Theme.of(context).dividerColor.withOpacity(0.6)), Container(margin: EdgeInsets.symmetric(vertical: 6.h), width: 12.w, height: 12.w, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(0.28), blurRadius: 8.r, offset: Offset(0, 4.h))])), Flexible(fit: FlexFit.loose, child: Container(width: 3.w, color: Theme.of(context).dividerColor.withOpacity(0.06)))])),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary.withOpacity(0.04), Theme.of(context).cardColor]),
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [BoxShadow(color: Theme.of(context).brightness == Brightness.dark ? Colors.black45 : Colors.black12, blurRadius: 22.r, offset: Offset(0, 10.h))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800))),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'edit', child: Text(AppLocalizations.of(context)!.edit)),
                          PopupMenuItem(value: 'delete', child: Text(AppLocalizations.of(context)!.delete)),
                        ],
                        onSelected: (v) {
                          if (v == 'edit') showPlanDialog(plan: plan);
                          if (v == 'delete') _showDeleteConfirmation(plan['id'].toString());
                        },
                        icon: Icon(Icons.more_vert, size: 18.sp, color: Theme.of(context).iconTheme.color?.withOpacity(0.7)),
                      ),
                    ],
                  ),
                  if (desc.isNotEmpty) ...[
                    SizedBox(height: 6.h),
                    Text(desc, style: TextStyle(fontSize: 13.sp, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.8)), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  SizedBox(height: 10.h),
                  Row(
                    children: [
                      Container(padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h), decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12, borderRadius: BorderRadius.circular(8.r)), child: Row(children: [Icon(Icons.schedule, size: 14.sp, color: Theme.of(context).textTheme.bodySmall?.color), SizedBox(width: 6.w), Text('$start ${end.isNotEmpty ? '• $end' : ''}', style: TextStyle(fontSize: 12.sp))])),
                      SizedBox(width: 8.w),
                      if (plan['tag'] != null) Container(padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8.r)), child: Text(plan['tag'].toString(), style: TextStyle(fontSize: 12.sp, color: color))),
                      const Spacer(),
                      IconButton(icon: Icon(Icons.delete_outline, color: Colors.red.shade300), onPressed: () => _showDeleteConfirmation(plan['id'].toString())),
                    ],
                  ),
                ],
              ),
            ),
          )
     ]));
    });
  }

  Widget _buildAnimatedTitle(AppLocalizations loc) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) => Transform.scale(
        scale: val,
        child: Opacity(opacity: val, child: child),
      ),
      child: Text(
        loc.programCalendar,
        style: TextStyle(fontSize: 25.sp, fontWeight: FontWeight.w800),
      ),
    );
  }
}


class PlanDialog extends StatefulWidget {
  final DateTime initialDate;
  final Map<String, dynamic>? plan; 
  final Function(Map<String, dynamic> data) onSave;

  const PlanDialog({
    super.key,
    required this.initialDate,
    this.plan,
    required this.onSave,
  });

  @override
  State<PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<PlanDialog> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _startTimeController;
  late final TextEditingController _endTimeController;

  final FocusNode _titleFocus = FocusNode();
  final FocusNode _descFocus = FocusNode();

  bool _appeared = false;
  bool _descFocused = false;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _titleController = TextEditingController(text: plan?['title'] ?? '');
    _descController = TextEditingController(text: plan?['description'] ?? '');
    _startTimeController = TextEditingController(text: plan?['start_time'] ?? '09:00');
    _endTimeController = TextEditingController(text: plan?['end_time'] ?? '10:00');

    _descFocus.addListener(() {
      if (mounted) setState(() => _descFocused = _descFocus.hasFocus);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _appeared = true);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _titleFocus.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  TimeOfDay? _parseHm(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
    final parsed = _parseHm(controller.text) ?? TimeOfDay(hour: 9, minute: 0);
    final selected = await showTimePicker(context: context, initialTime: parsed);
    if (selected != null) controller.text = '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final data = {
      'title': _titleController.text.trim(),
      'description': _descController.text.trim(),
      'start_time': _startTimeController.text.trim(),
      'end_time': _endTimeController.text.trim(),
      'date': DateFormat('yyyy-MM-dd').format(widget.initialDate),
    };
    widget.onSave(data);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.plan != null;
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AnimatedScale(
      scale: _appeared ? 1.0 : 0.98,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: _appeared ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 220),
        child: Dialog(
          insetPadding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 20.h),
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: 640.w,
                  maxHeight: MediaQuery.of(context).size.height * 0.58,
                ),
                decoration: BoxDecoration(
                  color: theme.dialogBackgroundColor.withOpacity(0.98),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.06)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20.r, offset: Offset(0, 10.h))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      builder: (context, val, child) => Transform.translate(
                        offset: Offset(0, (1 - val) * 8),
                        child: Opacity(opacity: val, child: child),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [theme.colorScheme.primary.withOpacity(0.98), theme.colorScheme.tertiary.withOpacity(0.9)]),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 56.r,
                              height: 56.r,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(DateFormat.d().format(widget.initialDate), style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 16.sp)),
                                    Text(DateFormat.E(Localizations.localeOf(context).toString()).format(widget.initialDate), style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.95), fontSize: 11.sp)),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(isEditing ? loc.editProgram : loc.newProgram, style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w800, color: theme.colorScheme.onPrimary)),
                                  SizedBox(height: 4.h),
                                  Text(DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(widget.initialDate), style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.92), fontSize: 12.sp)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: loc.cancel,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Flexible(
                      fit: FlexFit.loose,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
                        child: SingleChildScrollView(
                          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 12.h),
                          physics: const BouncingScrollPhysics(),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 44.r,
                                      height: 44.r,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(12.r),
                                      ),
                                      child: Icon(Icons.event_available, color: theme.colorScheme.tertiary, size: 20.sp),
                                    ),
                                    SizedBox(width: 12.w),
                                    Expanded(
                                      child: TextFormField(
                                        focusNode: _titleFocus,
                                        controller: _titleController,
                                        decoration: InputDecoration(
                                          labelText: loc.titleLabel,
                                          floatingLabelBehavior: FloatingLabelBehavior.auto,
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                                          filled: true,
                                          fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceVariant,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                                        ),
                                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                                        validator: (value) => (value == null || value.trim().isEmpty) ? loc.requiredField : null,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 14.h),

                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _startTimeController,
                                        decoration: InputDecoration(
                                          labelText: loc.startLabel,
                                          prefixIcon: Icon(Icons.schedule, size: 18.sp),
                                          filled: true,
                                          fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceVariant,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                                          suffixIcon: Icon(Icons.access_time_outlined, size: 18.sp),
                                        ),
                                        readOnly: true,
                                        onTap: () => _selectTime(context, _startTimeController),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) return loc.requiredField;
                                          return null;
                                        },
                                      ),
                                    ),
                                    SizedBox(width: 12.w),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _endTimeController,
                                        decoration: InputDecoration(
                                          labelText: loc.endLabel,
                                          prefixIcon: Icon(Icons.schedule, size: 18.sp),
                                          filled: true,
                                          fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceVariant,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                                          suffixIcon: Icon(Icons.access_time_outlined, size: 18.sp),
                                        ),
                                        readOnly: true,
                                        onTap: () => _selectTime(context, _endTimeController),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) return loc.requiredField;
                                          final s = _parseHm(_startTimeController.text);
                                          final e = _parseHm(value);
                                          if (s == null || e == null) return null;
                                          if (!e.isAfter(s)) return loc.endTimeError;
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 14.h),

                                AnimatedSize(
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeInOutCubic,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: theme.cardColor.withOpacity(0.02),
                                      borderRadius: BorderRadius.circular(12.r),
                                    ),
                                    padding: EdgeInsets.all(6.w),
                                    child: TextFormField(
                                      focusNode: _descFocus,
                                      controller: _descController,
                                      decoration: InputDecoration(
                                        labelText: loc.descriptionLabel,
                                        alignLabelWithHint: true,
                                        prefixIcon: Padding(padding: EdgeInsets.only(bottom: 8.h), child: Icon(Icons.short_text)),
                                        filled: true,
                                        fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceVariant,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: _descFocused ? 16.h : 12.h),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                                      ),
                                      minLines: _descFocused ? 4 : 2,
                                      maxLines: 6,
                                      style: TextStyle(fontSize: 14.sp),
                                    ),
                                  ),
                                ),
                                SizedBox(height: 18.h),

                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(vertical: 14.h),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                          side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.10)),
                                        ),
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: Text(loc.cancel, style: TextStyle(fontSize: 14.sp, color: theme.colorScheme.tertiary),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 12.w),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: Icon(Icons.check, size: 18.sp),
                                        label: Text(loc.save, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
                                        style: ElevatedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(vertical: 14.h),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                          backgroundColor: theme.colorScheme.primary,
                                        ),
                                        onPressed: _submit,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 6.h),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}