import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class ProgramPage extends StatefulWidget {
  final String idToken; // Firebase'den veya başka bir auth servisinden gelen token
  const ProgramPage({super.key, required this.idToken});

  @override
  State<ProgramPage> createState() => ProgramPageState();
}

class ProgramPageState extends State<ProgramPage> {
  final ApiService _apiService = ApiService();

  // Takvim ve sayfa durumu
  static const int _totalPages = 20000;
  late final PageController _pageController;
  DateTime _currentWeekStart;
  DateTime? _selectedDay;

  // Veri durumu
  bool _isLoading = true;
  String? _errorMessage;

  // Gruplanmış planlar (performans için)
  Map<String, List<Map<String, dynamic>>> _groupedPlans = {};

  ProgramPageState() : _currentWeekStart = _getStartOfWeek(DateTime.now());

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _pageController = PageController(initialPage: _totalPages ~/ 2);
    _selectedDay = DateTime(today.year, today.month, today.day);
    
    // initState'te async işlem yapmak için addPostFrameCallback kullanılır.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchPlansForWeek(_currentWeekStart);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // --- Yardımcı Fonksiyonlar ---

  static DateTime _getStartOfWeek(DateTime date) {
    // Pazartesi haftanın başlangıcıdır (weekday 1)
    return date.subtract(Duration(days: date.weekday - 1));
  }

  DateTime _getDateForPage(int pageIndex) {
    final weekOffset = pageIndex - (_totalPages ~/ 2);
    return _getStartOfWeek(DateTime.now()).add(Duration(days: weekOffset * 7));
  }

  void _groupAndSortPlans(List<Map<String, dynamic>> plans, {bool merge = false}) 
  {
    // Eğer birleştirme yapılıyorsa, yeni bir geçici harita oluştur.
    // Yoksa, sadece mevcut haftanın planlarını içeren geçici harita oluştur.
    final Map<String, List<Map<String, dynamic>>> newGrouped = {};

      // 1. Yeni verileri grupla
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

      // 2. Birleştirme (Merge) İşlemi
      if (merge) {
          // Mevcut haritanın bir kopyasını al (tüm haftalar)
          newGrouped.addAll(_groupedPlans);

          // Yeni gelen haftalık verileri, mevcut kopyanın üzerine yaz (replace)
          newlyGrouped.forEach((dateKey, plansList) {
              newGrouped[dateKey] = plansList;
          });
      } else {
          // Sadece yeni gelen haftalık veriyi kullan (mevcut haftayı ilk yükleme gibi)
          newGrouped.addAll(newlyGrouped);
      }

      // 3. Sıralama İşlemi
      newGrouped.forEach((date, planList) {
        planList.sort((a, b) {
          final startTimeA = a['start_time'] as String? ?? '00:00';
          final startTimeB = b['start_time'] as String? ?? '00:00';
          return startTimeA.compareTo(startTimeB);
        });
      });

      // State'i güncelle
      _groupedPlans = newGrouped;
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // --- API İşlemleri ---

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
      // ApiService'den gelen özel hataları yakala
      if (mounted) {
        setState(() {
          _errorMessage = e.message; // Gelişmiş hata mesajı
          _groupedPlans = {};
          _isLoading = false;
        });
      }
    } catch (e) {
      // Diğer genel hatalar için
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
      // Eğer API bize etkilenen planın tarihini döndüyse, o haftayı da yenile.
      DateTime? affectedDate;
      if (result is Map && result['date'] != null) {
        try {
          affectedDate = DateTime.parse(result['date'].toString());
        } catch (_) {
          affectedDate = null;
        }
      }

      // Hesapla: güncellenecek aralık = currentWeekStart ile affectedWeekStart arasındaki min..max hafta aralığı
      if (affectedDate != null) {
        final affectedWeekStart = _getStartOfWeek(affectedDate);
        final currentWeekStart = _currentWeekStart;
        final minStart = currentWeekStart.isBefore(affectedWeekStart) ? currentWeekStart : affectedWeekStart;
        final maxStart = currentWeekStart.isAfter(affectedWeekStart) ? currentWeekStart : affectedWeekStart;
        final rangeStart = minStart;
        final rangeEnd = maxStart.add(const Duration(days: 6));

        // yükleme gösterme olmadan birden fazla haftayı çek
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
          // Eğer fetch başarısız olursa, en azından mevcut haftayı yenile
          await _fetchPlansForWeek(_currentWeekStart, showLoading: false);
        }
      } else {
        // Etkilenen tarih yoksa en azından mevcut haftayı yenile
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

  // Yardımcı: bir planı groupedPlans içine ekle veya güncelle
  void _insertOrUpdatePlan(Map<String, dynamic> plan) {
    final dateKey = (plan['date'] as String).substring(0, 10);
    // önce mevcut her yerde aynı id varsa çıkar
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

  // Yardımcı: id'ye göre planı tüm gruplardan çıkar
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

  // DELETE: optimistik olarak UI'dan kaldır, API başarısız olursa geri koy
  void _onDeletePlan(String planId) async {
    // yedekle (ilk bulunan plan)
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

    // optimistik kaldır
    _removePlanById(planId);

    try {
      await _apiService.deletePlan(widget.idToken, planId);
      // başarılıysa sunucudan mevcut haftayı tazeleyebiliriz (opsiyonel)
      await _fetchPlansForWeek(_currentWeekStart, showLoading: false);
    } catch (e) {
      // hata -> geri koy
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
  
  // --- UI İşlemleri ---
  
  // Public method so MainScreen (via GlobalKey) can open the add/edit dialog.
  void showPlanDialog({Map<String, dynamic>? plan}) {
    final isEditing = plan != null;
    final date = isEditing ? DateTime.parse(plan['date']) : _selectedDay!;

    showDialog(
      context: context,
      builder: (context) {
        return PlanDialog(
          initialDate: date,
          plan: plan,
          onSave: (data) {
            if (isEditing) {
              _onUpdatePlan(plan['id'], data);
            } else {
              _onCreatePlan(data);
            }
          },
        );
      },
    );
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
  
  // --- Build Metotları ---

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.programCalendar),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: loc.today,
            onPressed: () {
              _pageController.animateToPage(
                _totalPages ~/ 2,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildWeekCalendar(),
            const Divider(height: 1),
            Expanded(child: _buildPlanList()),
          ],
        ),
      ),
      // Note: FAB is provided by MainScreen so it's rendered above the bottom nav.
    );
  }

  Widget _buildWeekCalendar() {
    return SizedBox(
      height: 100.h,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _totalPages,
        onPageChanged: (pageIndex) {
          final newWeekStart = _getDateForPage(pageIndex);
          setState(() {
            _currentWeekStart = newWeekStart;
            // Yeni haftaya geçerken seçili günü haftanın ilk gününe ayarla
            _selectedDay = newWeekStart;
          });
          _fetchPlansForWeek(newWeekStart);
        },
        itemBuilder: (context, pageIndex) {
          final weekStart = _getDateForPage(pageIndex);
          return _buildWeekView(weekStart);
        },
      ),
    );
  }

  Widget _buildWeekView(DateTime weekStart) {
    final dfDay = DateFormat.E(AppLocalizations.of(context)!.localeName);
    final dfNum = DateFormat.d(AppLocalizations.of(context)!.localeName);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(7, (index) {
          final day = weekStart.add(Duration(days: index));
          final isToday = _isSameDate(day, DateTime.now());
          final isSelected = _selectedDay != null && _isSameDate(day, _selectedDay!);
          final dateKey = DateFormat('yyyy-MM-dd').format(day);
          final hasPlans = _groupedPlans[dateKey]?.isNotEmpty ?? false;

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedDay = day),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(dfDay.format(day), style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  SizedBox(height: 6.h),
                  CircleAvatar(
                    radius: 16.r,
                    backgroundColor: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : (isToday ? Colors.grey.shade700 : Colors.transparent),
                    child: Text(dfNum.format(day), style: TextStyle(color: isSelected ? Colors.white : null)),
                  ),
                  SizedBox(height: 6.h),
                  if (hasPlans)
                    Container(
                      width: 6.w, height: 6.w,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary, shape: BoxShape.circle),
                    )
                  else
                    SizedBox(height: 6.w),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
  
  Widget _buildPlanList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
    }

    final key = _selectedDay != null ? DateFormat('yyyy-MM-dd').format(_selectedDay!) : null;
    final plansForDay = (key != null ? _groupedPlans[key] : null) ?? [];

    if (plansForDay.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined, size: 72.r, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.18)),
            SizedBox(height: 10.h),
            Text(AppLocalizations.of(context)!.noPlansHere, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7))),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
      itemCount: plansForDay.length,
      separatorBuilder: (_, __) => SizedBox(height: 12.h),
      itemBuilder: (context, index) {
        final plan = plansForDay[index];
        final start = plan['start_time'] ?? '';
        final end = plan['end_time'] ?? '';
        final title = plan['title'] ?? '';
        final desc = (plan['description'] ?? '').toString();
        final color = Theme.of(context).colorScheme.primary;

        return GestureDetector(
          onTap: () => showPlanDialog(plan: plan),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time column + vertical line
              SizedBox(
                width: 72.w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(start, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.85))),
                    if ((end ?? '').isNotEmpty) Text(end, style: TextStyle(fontSize: 11.sp, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7))),
                    SizedBox(height: 6.h),
                  ],
                ),
              ),

              // Timeline indicators
              Container(
                width: 28.w,
                alignment: Alignment.topCenter,
                child: Column(
                  children: [
                    Container(width: 3.w, height: 12.h, color: Theme.of(context).dividerColor.withOpacity(0.6)),
                    Container(
                      margin: EdgeInsets.symmetric(vertical: 6.h),
                      width: 12.w,
                      height: 12.w,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: color.withOpacity(0.28), blurRadius: 8.r, offset: Offset(0, 4.h))],
                      ),
                    ),
                    Expanded(child: Container(width: 3.w, color: Theme.of(context).dividerColor.withOpacity(0.06))),
                  ],
                ),
              ),

              // Card content
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14.r),
                    boxShadow: [
                      BoxShadow(color: Theme.of(context).brightness == Brightness.dark ? Colors.black45 : Colors.black12, blurRadius: 18.r, offset: Offset(0, 8.h)),
                    ],
                    border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800, color: Theme.of(context).textTheme.bodyLarge?.color)),
                          ),
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'edit', child: Text(AppLocalizations.of(context)!.edit)),
                              PopupMenuItem(value: 'delete', child: Text(AppLocalizations.of(context)!.delete)),
                            ],
                            onSelected: (v) {
                              if (v == 'edit') showPlanDialog(plan: plan);
                              if (v == 'delete') _showDeleteConfirmation(plan['id']);
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
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12,
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.schedule, size: 14.sp, color: Theme.of(context).textTheme.bodySmall?.color),
                                SizedBox(width: 6.w),
                                Text('$start ${end.isNotEmpty ? '• $end' : ''}', style: TextStyle(fontSize: 12.sp)),
                              ],
                            ),
                          ),
                          SizedBox(width: 8.w),
                          // example tag, if plan has tags show them (soft)
                          if (plan['tag'] != null)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8.r)),
                              child: Text(plan['tag'].toString(), style: TextStyle(fontSize: 12.sp, color: color)),
                            ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
                            onPressed: () => _showDeleteConfirmation(plan['id']),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


// --- YENİDEN KULLANILABİLİR WIDGET ---

class PlanDialog extends StatefulWidget {
  final DateTime initialDate;
  final Map<String, dynamic>? plan; // Düzenleme modu için
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

  bool _appeared = false;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _titleController = TextEditingController(text: plan?['title'] ?? '');
    _descController = TextEditingController(text: plan?['description'] ?? '');
    _startTimeController = TextEditingController(text: plan?['start_time'] ?? '09:00');
    _endTimeController = TextEditingController(text: plan?['end_time'] ?? '10:00');

    // küçük giriş animasyonu için flag'i aç
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
    super.dispose();
  }
  
  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
    final initialParts = controller.text.split(RegExp(r'[:\s]'));
    int ih = 9, im = 0;
    if (initialParts.isNotEmpty) {
      try {
        final p = initialParts[0].padLeft(2, '0');
        ih = int.parse(p);
        if (initialParts.length > 1) im = int.parse(initialParts[1]);
      } catch (_) {}
    }
    final initial = TimeOfDay(hour: ih, minute: im);
    final selectedTime = await showTimePicker(context: context, initialTime: initial);
    if (selectedTime != null) {
      controller.text = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
    }
  }

  DateTime? _parseHm(String s) {
    try {
      final parts = s.split(':');
      if (parts.length < 2) return null;
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, h, m);
    } catch (_) {
      return null;
    }
  }
  
  void _submit() {
    if (_formKey.currentState!.validate()) {
      final data = {
        'date': DateFormat('yyyy-MM-dd').format(widget.initialDate),
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'start_time': _startTimeController.text,
        'end_time': _endTimeController.text,
      };
      widget.onSave(data);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.plan != null;
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // Animated scale + fade for smoother appearance
    return AnimatedScale(
      scale: _appeared ? 1.0 : 0.98,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: _appeared ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 220),
        child: Dialog(
          insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
          backgroundColor: theme.dialogBackgroundColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 540.w),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 18.h),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 56.r,
                          height: 56.r,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8.r, offset: Offset(0,4.h))],
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(DateFormat.d().format(widget.initialDate), style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 16.sp)),
                                Text(DateFormat.E(Localizations.localeOf(context).toString()).format(widget.initialDate), style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.9), fontSize: 11.sp)),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 14.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isEditing ? loc.editProgram : loc.newProgram, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
                              SizedBox(height: 4.h),
                              Text(DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(widget.initialDate), style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 12.sp)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _titleController,
                            decoration: InputDecoration(
                              labelText: loc.titleLabel,
                              prefixIcon: Icon(Icons.title_outlined),
                              filled: true,
                              fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceVariant,
                              contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                            ),
                            validator: (value) => (value == null || value.trim().isEmpty) ? loc.requiredField : null,
                          ),
                          SizedBox(height: 12.h),
                          TextFormField(
                            controller: _descController,
                            decoration: InputDecoration(
                              labelText: loc.descriptionLabel,
                              prefixIcon: Icon(Icons.short_text),
                              filled: true,
                              fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceVariant,
                              contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                            ),
                            minLines: 1,
                            maxLines: 3,
                          ),
                          SizedBox(height: 12.h),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _startTimeController,
                                  decoration: InputDecoration(
                                    labelText: loc.startLabel,
                                    prefixIcon: Icon(Icons.schedule),
                                    filled: true,
                                    fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceVariant,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                                    suffixIcon: Icon(Icons.access_time_outlined),
                                  ),
                                  readOnly: true,
                                  onTap: () => _selectTime(context, _startTimeController),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) return loc.requiredField;
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: TextFormField(
                                  controller: _endTimeController,
                                  decoration: InputDecoration(
                                    labelText: loc.endLabel,
                                    prefixIcon: Icon(Icons.schedule),
                                    filled: true,
                                    fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceVariant,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                                    suffixIcon: Icon(Icons.access_time_outlined),
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
                          SizedBox(height: 18.h),

                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(vertical: 14.h),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                    side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.12)),
                                    foregroundColor: theme.colorScheme.onSurface,
                                  ),
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: Text(loc.cancel, style: TextStyle(fontSize: 14.sp)),
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: Icon(Icons.check, size: 18.sp),
                                  label: Text(loc.save, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(vertical: 14.h),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor: theme.colorScheme.onPrimary, // ensures text/icon contrast
                                  ),
                                  onPressed: _submit,
                                ),
                              ),
                            ],
                          ),
                        ],
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