// lib/pages/program_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'package:collection/collection.dart';
import '../l10n/app_localizations.dart';
import '../providers/user_provider.dart';
import '../main_screen.dart';

class ProgramPage extends StatefulWidget {
  final String idToken;
  const ProgramPage({super.key, required this.idToken});

  @override
  State<ProgramPage> createState() => _ProgramPageState();
}

class _ProgramPageState extends State<ProgramPage> with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();

  // calendar/page state
  static const int _totalPages = 20000;
  late final int _initialPage;
  late final PageController _pageController;
  late DateTime _today;
  DateTime? _currentWeekStart;

  // plans for currently visible week
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _plans = [];

  // selected day (for highlighting / create)
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _initialPage = _totalPages ~/ 2;
    _pageController = PageController(initialPage: _initialPage);
    _currentWeekStart = _startOfWeek(_today);
    _selectedDay = DateTime(_today.year, _today.month, _today.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPlansForWeek(_currentWeekStart!));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _startOfWeek(DateTime dt) {
    // week starts on Monday
    final weekday = dt.weekday; // Mon=1 .. Sun=7
    return DateTime(dt.year, dt.month, dt.day).subtract(Duration(days: weekday - 1));
  }

  List<DateTime> _generateWeek(DateTime start) {
    return List.generate(7, (i) => DateTime(start.year, start.month, start.day + i));
  }

  DateTime _startDateForPage(int pageIndex) {
    final int weekOffset = pageIndex - _initialPage;
    return DateTime(_today.year, _today.month, _today.day + weekOffset * 7);
  }

  Future<void> _loadPlansForWeek(DateTime weekStart) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = DateTime(start.year, start.month, start.day + 6);
    try {
      final plans = await _apiService.getUserPlans(widget.idToken, start, end);
      setState(() {
        _plans = plans;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _plans = [];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupPlansByDate() {
    // group by date string yyyy-MM-dd
    final df = DateFormat('yyyy-MM-dd');
    return groupBy(_plans, (Map p) => df.format(DateTime.parse(p['date'].toString())));
  }

  Future<void> _showCreatePlanDialog(DateTime date) async {
    final titleCtrl = TextEditingController();
    final startCtrl = TextEditingController(text: "09:00");
    final endCtrl = TextEditingController(text: "10:00");
    final descCtrl = TextEditingController();
    final loc = AppLocalizations.of(context)!;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(loc.newProgram),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: titleCtrl, decoration: InputDecoration(labelText: loc.titleLabel)),
                TextField(controller: startCtrl, decoration: InputDecoration(labelText: loc.startLabel)),
                TextField(controller: endCtrl, decoration: InputDecoration(labelText: loc.endLabel)),
                TextField(controller: descCtrl, decoration: InputDecoration(labelText: loc.descriptionLabel)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.save)),
          ],
        );
      },
    );

    if (ok != true) return;
    // build payload
    final df = DateFormat('yyyy-MM-dd');
    final payload = {
      'date': df.format(date),
      'start_time': startCtrl.text.trim(),
      'end_time': endCtrl.text.trim(),
      'title': titleCtrl.text.trim().isEmpty ? loc.defaultProgramTitle : titleCtrl.text.trim(),
      'description': descCtrl.text.trim(),
    };

    try {
      await _apiService.createPlan(widget.idToken, payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.planCreated), backgroundColor: Colors.green));
      await _loadPlansForWeek(_currentWeekStart!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${loc.errorOccurred}: ${e.toString()}"), backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  Future<void> _deletePlan(String id) async {
    try {
      await _api_service.deletePlan(widget.idToken, id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.planDeleted), backgroundColor: Colors.green));
      await _loadPlansForWeek(_currentWeekStart!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${AppLocalizations.of(context)!.errorOccurred}: ${e.toString()}"), backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dfDay = DateFormat.E(); // Mon, Tue...
    final dfNum = DateFormat.d();
    final loc = AppLocalizations.of(context)!;

    final grouped = _groupPlansByDate();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.programCalendar),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: loc.refresh,
            onPressed: _currentWeekStart != null ? () => _loadPlansForWeek(_currentWeekStart!) : null,
          )
        ],
      ),
      body: Column(
        children: [
          SizedBox(height: 12.h),
          SizedBox(
            height: 96.h,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _totalPages,
              onPageChanged: (idx) {
                final s = _startOfWeek(_startDateForPage(idx));
                setState(() {
                  _currentWeekStart = s;
                  _selectedDay = s;
                });
                _loadPlansForWeek(s);
              },
              itemBuilder: (context, pageIndex) {
                final weekStart = _startOfWeek(_startDateForPage(pageIndex));
                final days = _generateWeek(weekStart);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Row(
                    children: days.map((d) {
                      final isToday = _isSameDate(d, DateTime.now());
                      final isSelected = _selectedDay != null && _isSameDate(d, _selectedDay!);
                      final dateKey = DateFormat('yyyy-MM-dd').format(d);
                      final hasPlans = grouped[dateKey]?.isNotEmpty ?? false;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedDay = d);
                          },
                          onLongPress: () => _showCreatePlanDialog(d),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4.0),
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            decoration: BoxDecoration(
                              color: isSelected ? theme.colorScheme.primary.withOpacity(0.12) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10.r),
                              border: Border.all(color: isSelected ? theme.colorScheme.primary.withOpacity(0.22) : Colors.transparent),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(dfDay.format(d), style: TextStyle(color: isSelected ? theme.colorScheme.primary : Colors.white70)),
                                const SizedBox(height: 6),
                                CircleAvatar(
                                  radius: 18.r,
                                  backgroundColor: isToday ? theme.colorScheme.primary : Colors.white12,
                                  child: Text(dfNum.format(d), style: TextStyle(color: isToday ? Colors.black : Colors.white)),
                                ),
                                const SizedBox(height: 6),
                                if (hasPlans)
                                  Container(
                                    width: 8.w,
                                    height: 8.w,
                                    decoration: BoxDecoration(color: theme.colorScheme.secondary, shape: BoxShape.circle),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          // list of plans for selected day
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                : _error != null
                    ? Center(child: Text("${loc.errorOccurred}: $_error", style: TextStyle(color: theme.colorScheme.error)))
                    : _buildPlansListForSelectedDay(grouped),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _selectedDay != null ? () => _showCreatePlanDialog(_selectedDay!) : null,
        tooltip: loc.add,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildPlansListForSelectedDay(Map<String, List<Map<String, dynamic>>> grouped) {
    final df = DateFormat('yyyy-MM-dd');
    final loc = AppLocalizations.of(context)!;
    final key = _selectedDay != null ? df.format(_selectedDay!) : null;
    final list = key != null ? (grouped[key] ?? []) : [];

    if (list.isEmpty) {
      return Center(
        child: Text(loc.noPlansMessage, textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
      );
    }

    // sort by start_time
    list.sort((a, b) {
      final sa = a['start_time'] as String? ?? '';
      final sb = b['start_time'] as String? ?? '';
      return sa.compareTo(sb);
    });

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final item = list[idx];
        final start = item['start_time'] as String? ?? '';
        final end = item['end_time'] as String? ?? '';
        final title = item['title'] as String? ?? '';
        final desc = item['description'] as String? ?? '';
        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          child: ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("$start - $end\n$desc", maxLines: 3, overflow: TextOverflow.ellipsis),
            isThreeLine: desc.isNotEmpty,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(loc.delete),
                    content: Text(loc.deleteConfirm),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.delete)),
                    ],
                  ),
                );
                if (ok == true) {
                  await _deletePlan(item['id'] as String);
                }
              },
            ),
          ),
        );
      },
    );
  }
}