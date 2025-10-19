import 'package:flutter_test/flutter_test.dart';
import 'package:flow7/utils/date_utils.dart';

void main() {
  group('Date Utils Tests', () {
    test('generateWeekDays should generate 7 days starting from given date', () {
      final startDate = DateTime(2024, 1, 1); // Monday, January 1, 2024
      final weekDays = generateWeekDays(startDate: startDate);

      expect(weekDays.length, 7);
      expect(weekDays[0], DateTime(2024, 1, 1));
      expect(weekDays[6], DateTime(2024, 1, 7));
    });

    test('generateWeekDays should default to today when no startDate is provided', () {
      final weekDays = generateWeekDays();
      final today = DateTime.now();
      final todayNormalized = DateTime(today.year, today.month, today.day);

      expect(weekDays.length, 7);
      expect(weekDays[0], todayNormalized);
    });

    test('generateWeekDays should normalize dates to midnight', () {
      final startDate = DateTime(2024, 1, 1, 15, 30, 45); // With time
      final weekDays = generateWeekDays(startDate: startDate);

      // All days should be at midnight
      for (var day in weekDays) {
        expect(day.hour, 0);
        expect(day.minute, 0);
        expect(day.second, 0);
      }
    });

    test('getWeekStart should return Monday for any day of the week', () {
      // Test various days of a week
      final monday = DateTime(2024, 1, 1); // Monday
      final wednesday = DateTime(2024, 1, 3); // Wednesday
      final sunday = DateTime(2024, 1, 7); // Sunday

      expect(getWeekStart(monday), DateTime(2024, 1, 1));
      expect(getWeekStart(wednesday), DateTime(2024, 1, 1));
      expect(getWeekStart(sunday), DateTime(2024, 1, 1));
    });

    test('getWeekStart should normalize date to midnight', () {
      final date = DateTime(2024, 1, 3, 15, 30, 45); // Wednesday with time
      final weekStart = getWeekStart(date);

      expect(weekStart.hour, 0);
      expect(weekStart.minute, 0);
      expect(weekStart.second, 0);
    });

    test('generateWeekDays should handle month boundaries correctly', () {
      final startDate = DateTime(2024, 1, 29); // Last days of January
      final weekDays = generateWeekDays(startDate: startDate);

      expect(weekDays.length, 7);
      expect(weekDays[0], DateTime(2024, 1, 29));
      expect(weekDays[3], DateTime(2024, 2, 1)); // Should be in February
      expect(weekDays[6], DateTime(2024, 2, 4));
    });

    test('generateWeekDays should handle year boundaries correctly', () {
      final startDate = DateTime(2023, 12, 28); // Last days of 2023
      final weekDays = generateWeekDays(startDate: startDate);

      expect(weekDays.length, 7);
      expect(weekDays[0], DateTime(2023, 12, 28));
      expect(weekDays[4], DateTime(2024, 1, 1)); // Should be in 2024
      expect(weekDays[6], DateTime(2024, 1, 3));
    });
  });
}
