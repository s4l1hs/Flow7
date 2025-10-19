import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user_tier.dart';

class WeeklyCalendar extends StatefulWidget {
  final DateTime initialDate;
  final UserTier userTier;
  final Function(DateTime) onDateSelected;
  final DateTime? selectedDate;

  const WeeklyCalendar({
    Key? key,
    required this.initialDate,
    required this.userTier,
    required this.onDateSelected,
    this.selectedDate,
  }) : super(key: key);

  @override
  State<WeeklyCalendar> createState() => _WeeklyCalendarState();
}

class _WeeklyCalendarState extends State<WeeklyCalendar> {
  late PageController _pageController;
  late int _currentPageIndex;

  @override
  void initState() {
    super.initState();
    // Start at a high index to allow scrolling both ways
    _currentPageIndex = 1000;
    _pageController = PageController(
      initialPage: _currentPageIndex,
      viewportFraction: 1.0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _getWeekStartDate(int pageIndex) {
    final daysDifference = (pageIndex - _currentPageIndex) * 7;
    final weekStart = widget.initialDate.add(Duration(days: daysDifference));
    // Get the start of the week (Monday)
    return weekStart.subtract(Duration(days: weekStart.weekday - 1));
  }

  bool _isDateAllowed(DateTime date) {
    final now = DateTime.now();
    final maxDate = now.add(Duration(days: widget.userTier.maxDaysAccess));
    
    // Normalize dates to midnight for comparison
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedNow = DateTime(now.year, now.month, now.day);
    final normalizedMax = DateTime(maxDate.year, maxDate.month, maxDate.day);
    
    return !normalizedDate.isBefore(normalizedNow) && 
           !normalizedDate.isAfter(normalizedMax);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tier indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Plan up to ${widget.userTier.maxDaysAccess} days ahead',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _getTierColor(),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.userTier.name,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Calendar
        SizedBox(
          height: 100,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPageIndex = index;
              });
            },
            itemBuilder: (context, pageIndex) {
              return _buildWeekView(_getWeekStartDate(pageIndex));
            },
          ),
        ),
      ],
    );
  }

  Color _getTierColor() {
    switch (widget.userTier) {
      case UserTier.free:
        return Colors.grey;
      case UserTier.pro:
        return Colors.blue;
      case UserTier.ultra:
        return Colors.purple;
    }
  }

  Widget _buildWeekView(DateTime weekStart) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (index) {
        final date = weekStart.add(Duration(days: index));
        final isAllowed = _isDateAllowed(date);
        final isSelected = widget.selectedDate != null &&
            date.year == widget.selectedDate!.year &&
            date.month == widget.selectedDate!.month &&
            date.day == widget.selectedDate!.day;
        final isToday = _isToday(date);

        return Expanded(
          child: GestureDetector(
            onTap: isAllowed
                ? () => widget.onDateSelected(date)
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Date is outside your ${widget.userTier.name} plan limit '
                          '(${widget.userTier.maxDaysAccess} days)',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : isToday
                        ? Theme.of(context).primaryColor.withOpacity(0.2)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isAllowed
                      ? (isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey.shade300)
                      : Colors.red.shade200,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('EEE').format(date),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isAllowed
                          ? (isSelected ? Colors.white : Colors.grey[600])
                          : Colors.red.shade300,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d').format(date),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isAllowed
                          ? (isSelected ? Colors.white : Colors.black87)
                          : Colors.red.shade300,
                    ),
                  ),
                  if (!isAllowed)
                    Icon(
                      Icons.lock,
                      size: 12,
                      color: Colors.red.shade300,
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}
