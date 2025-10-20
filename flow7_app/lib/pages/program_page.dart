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

  void _groupAndSortPlans(List<Map<String, dynamic>> plans) {
    // Planları tarihe göre grupla
    final grouped = groupBy(plans, (plan) => (plan['date'] as String).substring(0, 10));
    
    // Her günün planlarını başlangıç saatine göre sırala
    grouped.forEach((date, planList) {
      planList.sort((a, b) {
        final startTimeA = a['start_time'] as String? ?? '00:00';
        final startTimeB = b['start_time'] as String? ?? '00:00';
        return startTimeA.compareTo(startTimeB);
      });
    });
    _groupedPlans = grouped;
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
          _groupAndSortPlans(plans);
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
              _groupAndSortPlans(plans);
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

  void _onDeletePlan(String planId) {
    _handleApiResponse(_apiService.deletePlan(widget.idToken, planId));
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
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
      // Boş gün: kullanıcıya metin ile yönlendirme gösterilmesin.
      // Sadece hafif bir ikon gösteriyoruz; plan eklemek için sağ-alt + tuşunu kullanın.
      return Center(
        child: Icon(Icons.event_note_outlined, size: 72.r, color: Colors.grey.shade400),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(8.w),
      itemCount: plansForDay.length,
      itemBuilder: (context, index) {
        final plan = plansForDay[index];
        return Card(
          margin: EdgeInsets.symmetric(vertical: 4.h, horizontal: 8.w),
          child: ListTile(
            onTap: () => showPlanDialog(plan: plan), // DÜZENLEME İÇİN
            leading: Text(
              plan['start_time'] ?? '',
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
            ),
            title: Text(plan['title'] ?? ''),
            subtitle: plan['description'] != null && (plan['description'] as String).isNotEmpty
                ? Text(plan['description'], maxLines: 1, overflow: TextOverflow.ellipsis)
                : null,
            trailing: IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
              onPressed: () => _showDeleteConfirmation(plan['id']),
            ),
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

class _PlanDialogState extends State<PlanDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _startTimeController;
  late final TextEditingController _endTimeController;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _titleController = TextEditingController(text: plan?['title'] ?? '');
    _descController = TextEditingController(text: plan?['description'] ?? '');
    // normalize to HH:mm (24h) for consistent display/comparison
    _startTimeController = TextEditingController(text: plan?['start_time'] ?? '09:00');
    _endTimeController = TextEditingController(text: plan?['end_time'] ?? '10:00');
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
      // use 24h HH:mm format for consistency
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

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
      backgroundColor: theme.dialogBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520.w),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 18.h),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with date badge and title
                Row(
                  children: [
                    Container(
                      width: 56.r,
                      height: 56.r,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(DateFormat.d().format(widget.initialDate), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.sp)),
                            Text(DateFormat.E(Localizations.localeOf(context).toString()).format(widget.initialDate), style: TextStyle(color: Colors.white70, fontSize: 11.sp)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 14.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isEditing ? loc.editProgram : loc.newProgram, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
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
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 14.h),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                foregroundColor: theme.colorScheme.onSurface,
                                backgroundColor: theme.colorScheme.surfaceVariant,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(loc.cancel, style: TextStyle(fontSize: 14.sp)),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 14.h),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                backgroundColor: theme.colorScheme.primary,
                                elevation: 3,
                              ),
                              onPressed: _submit,
                              child: Text(loc.save, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
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
    );
  }
}