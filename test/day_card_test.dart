import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow7/widgets/day_card.dart';

void main() {
  group('DayCard Widget Tests', () {
    testWidgets('DayCard displays day of week and date number', (WidgetTester tester) async {
      final testDate = DateTime(2024, 1, 15); // Monday, January 15, 2024

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayCard(date: testDate),
          ),
        ),
      );

      // Check if the day of week is displayed
      expect(find.text('Mon'), findsOneWidget);
      
      // Check if the date number is displayed
      expect(find.text('15'), findsOneWidget);
    });

    testWidgets('DayCard highlights today with different styling', (WidgetTester tester) async {
      final testDate = DateTime(2024, 1, 15);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayCard(date: testDate, isToday: true),
          ),
        ),
      );

      // Find the Card widget
      final cardFinder = find.byType(Card);
      expect(cardFinder, findsOneWidget);

      final card = tester.widget<Card>(cardFinder);
      
      // Today should have higher elevation
      expect(card.elevation, 4.0);
    });

    testWidgets('DayCard uses normal styling when not today', (WidgetTester tester) async {
      final testDate = DateTime(2024, 1, 15);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayCard(date: testDate, isToday: false),
          ),
        ),
      );

      // Find the Card widget
      final cardFinder = find.byType(Card);
      expect(cardFinder, findsOneWidget);

      final card = tester.widget<Card>(cardFinder);
      
      // Normal day should have lower elevation
      expect(card.elevation, 1.0);
    });
  });
}
