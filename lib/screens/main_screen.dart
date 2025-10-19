import 'package:flutter/material.dart';
import '../utils/date_utils.dart' as date_utils;
import '../widgets/day_card.dart';

/// Main screen displaying a 7-day calendar view with horizontal scrolling.
/// 
/// Users can swipe left/right to navigate between weeks.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late PageController _pageController;
  late DateTime _currentWeekStart;
  
  // Initial page is set to a high number to allow scrolling backwards
  final int _initialPage = 10000;

  @override
  void initState() {
    super.initState();
    _currentWeekStart = date_utils.getWeekStart(DateTime.now());
    _pageController = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Get the start date for a given page index
  DateTime _getWeekStartForPage(int page) {
    final offset = page - _initialPage;
    return _currentWeekStart.add(Duration(days: offset * 7));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flow7'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (page) {
          setState(() {
            _currentWeekStart = _getWeekStartForPage(page);
          });
        },
        itemBuilder: (context, page) {
          final weekStart = _getWeekStartForPage(page);
          final weekDays = date_utils.generateWeekDays(startDate: weekStart);
          final today = DateTime.now();
          final todayNormalized = DateTime(today.year, today.month, today.day);

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Week header
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Text(
                    _getWeekRangeText(weekDays),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                // 7-day view
                Expanded(
                  child: ListView.builder(
                    itemCount: weekDays.length,
                    itemBuilder: (context, index) {
                      final day = weekDays[index];
                      final dayNormalized = DateTime(day.year, day.month, day.day);
                      final isToday = dayNormalized.isAtSameMomentAs(todayNormalized);

                      return DayCard(
                        date: day,
                        isToday: isToday,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Generate a text representation of the week range
  String _getWeekRangeText(List<DateTime> weekDays) {
    if (weekDays.isEmpty) return '';
    
    final first = weekDays.first;
    final last = weekDays.last;
    
    // Format based on whether the week spans multiple months
    if (first.month == last.month) {
      return '${_monthName(first.month)} ${first.day} - ${last.day}, ${first.year}';
    } else if (first.year == last.year) {
      return '${_monthName(first.month)} ${first.day} - ${_monthName(last.month)} ${last.day}, ${first.year}';
    } else {
      return '${_monthName(first.month)} ${first.day}, ${first.year} - ${_monthName(last.month)} ${last.day}, ${last.year}';
    }
  }

  /// Get month name from month number
  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }
}
