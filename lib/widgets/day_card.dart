import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A card widget representing a single day in the calendar view.
/// 
/// Displays the day of the week (e.g., Mon, Tue) and the date number.
class DayCard extends StatelessWidget {
  final DateTime date;
  final bool isToday;

  const DayCard({
    super.key,
    required this.date,
    this.isToday = false,
  });

  @override
  Widget build(BuildContext context) {
    final dayOfWeek = DateFormat('EEE').format(date); // e.g., Mon, Tue
    final dayNumber = DateFormat('d').format(date); // e.g., 1, 2, 15

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Card(
        elevation: isToday ? 4.0 : 1.0,
        color: isToday ? Theme.of(context).colorScheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dayOfWeek,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: isToday
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                dayNumber,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isToday
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
