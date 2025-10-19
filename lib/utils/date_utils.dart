/// Utility functions for date operations in Flow7

/// Generates an array of 7 days starting from a given startDate.
/// 
/// [startDate] defaults to today if not provided.
/// Returns a list of DateTime objects representing 7 consecutive days.
List<DateTime> generateWeekDays({DateTime? startDate}) {
  final start = startDate ?? DateTime.now();
  
  // Normalize the date to midnight to avoid time-of-day issues
  final normalizedStart = DateTime(start.year, start.month, start.day);
  
  return List.generate(7, (index) {
    return normalizedStart.add(Duration(days: index));
  });
}

/// Gets the start of the week (Monday) for a given date.
/// 
/// This is useful for ensuring weeks always start on Monday.
DateTime getWeekStart(DateTime date) {
  final normalizedDate = DateTime(date.year, date.month, date.day);
  final weekday = normalizedDate.weekday;
  
  // weekday is 1 (Monday) to 7 (Sunday)
  // Subtract (weekday - 1) to get to Monday
  return normalizedDate.subtract(Duration(days: weekday - 1));
}
