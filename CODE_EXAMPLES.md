# Code Examples and Usage

This document provides key code examples from the implementation.

## 1. Using the Date Utilities

### Generate 7 Days from Today
\`\`\`dart
import 'package:flow7/utils/date_utils.dart';

// Get 7 days starting from today
final weekDays = generateWeekDays();
// Returns: [today, today+1, today+2, ..., today+6]
\`\`\`

### Generate 7 Days from Specific Date
\`\`\`dart
import 'package:flow7/utils/date_utils.dart';

final startDate = DateTime(2024, 1, 15);
final weekDays = generateWeekDays(startDate: startDate);
// Returns: [Jan 15, Jan 16, Jan 17, ..., Jan 21]
\`\`\`

### Get Week Start (Monday)
\`\`\`dart
import 'package:flow7/utils/date_utils.dart';

final someDate = DateTime(2024, 1, 17); // Wednesday
final monday = getWeekStart(someDate);
// Returns: Jan 15, 2024 (Monday of that week)
\`\`\`

## 2. Using the DayCard Widget

### Basic DayCard
\`\`\`dart
import 'package:flow7/widgets/day_card.dart';

DayCard(
  date: DateTime(2024, 1, 15),
)
\`\`\`

### Highlighted DayCard (Today)
\`\`\`dart
import 'package:flow7/widgets/day_card.dart';

DayCard(
  date: DateTime.now(),
  isToday: true,  // Highlights the card
)
\`\`\`

## 3. Main Screen Implementation

### Complete MainScreen Example
\`\`\`dart
import 'package:flutter/material.dart';
import 'package:flow7/screens/main_screen.dart';

void main() {
  runApp(MaterialApp(
    home: MainScreen(),
  ));
}
\`\`\`

### Key Code from main_screen.dart

#### State Initialization
\`\`\`dart
class _MainScreenState extends State<MainScreen> {
  late PageController _pageController;
  late DateTime _currentWeekStart;
  final int _initialPage = 10000;

  @override
  void initState() {
    super.initState();
    _currentWeekStart = date_utils.getWeekStart(DateTime.now());
    _pageController = PageController(initialPage: _initialPage);
  }
}
\`\`\`

#### PageView with Week Navigation
\`\`\`dart
PageView.builder(
  controller: _pageController,
  onPageChanged: (page) {
    setState(() {
      _currentWeekStart = _getWeekStartForPage(page);
    });
  },
  itemBuilder: (context, page) {
    final weekStart = _getWeekStartForPage(page);
    final weekDays = date_utils.generateWeekDays(startDate: weekStart);
    
    // Build week view...
  },
)
\`\`\`

#### Week Offset Calculation
\`\`\`dart
DateTime _getWeekStartForPage(int page) {
  final offset = page - _initialPage;
  return _currentWeekStart.add(Duration(days: offset * 7));
}
\`\`\`

## 4. Testing Examples

### Unit Test for Date Generation
\`\`\`dart
test('generateWeekDays should generate 7 days starting from given date', () {
  final startDate = DateTime(2024, 1, 1);
  final weekDays = generateWeekDays(startDate: startDate);

  expect(weekDays.length, 7);
  expect(weekDays[0], DateTime(2024, 1, 1));
  expect(weekDays[6], DateTime(2024, 1, 7));
});
\`\`\`

### Widget Test for DayCard
\`\`\`dart
testWidgets('DayCard displays day of week and date number', (tester) async {
  final testDate = DateTime(2024, 1, 15);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DayCard(date: testDate),
      ),
    ),
  );

  expect(find.text('Mon'), findsOneWidget);
  expect(find.text('15'), findsOneWidget);
});
\`\`\`

## 5. Customization Examples

### Custom Theme Colors
\`\`\`dart
MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.purple,  // Change primary color
    ),
    useMaterial3: true,
  ),
  home: MainScreen(),
)
\`\`\`

### Dark Theme Support
\`\`\`dart
MaterialApp(
  theme: ThemeData.light(),
  darkTheme: ThemeData.dark(),
  themeMode: ThemeMode.system,  // Follows system setting
  home: MainScreen(),
)
\`\`\`

## 6. Advanced Usage

### Custom Week Start Day
\`\`\`dart
// To start week on Sunday instead of Monday,
// modify getWeekStart in date_utils.dart:

DateTime getWeekStart(DateTime date) {
  final normalizedDate = DateTime(date.year, date.month, date.day);
  final weekday = normalizedDate.weekday;
  
  // For Sunday start, adjust calculation:
  final daysToSubtract = weekday == 7 ? 0 : weekday;
  return normalizedDate.subtract(Duration(days: daysToSubtract));
}
\`\`\`

### Programmatic Navigation
\`\`\`dart
class _MainScreenState extends State<MainScreen> {
  // ... existing code ...

  void goToNextWeek() {
    _pageController.nextPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void goToPreviousWeek() {
    _pageController.previousPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}
\`\`\`

## 7. Date Formatting Examples

### Format Week Range
\`\`\`dart
String _getWeekRangeText(List<DateTime> weekDays) {
  if (weekDays.isEmpty) return '';
  
  final first = weekDays.first;
  final last = weekDays.last;
  
  if (first.month == last.month) {
    return '\${_monthName(first.month)} \${first.day} - \${last.day}, \${first.year}';
  } else if (first.year == last.year) {
    return '\${_monthName(first.month)} \${first.day} - \${_monthName(last.month)} \${last.day}, \${first.year}';
  } else {
    return '\${_monthName(first.month)} \${first.day}, \${first.year} - \${_monthName(last.month)} \${last.day}, \${last.year}';
  }
}
\`\`\`

## 8. Common Patterns

### Checking if Date is Today
\`\`\`dart
bool isDateToday(DateTime date) {
  final today = DateTime.now();
  final normalizedToday = DateTime(today.year, today.month, today.day);
  final normalizedDate = DateTime(date.year, date.month, date.day);
  return normalizedDate.isAtSameMomentAs(normalizedToday);
}
\`\`\`

### Iterating Through Week Days
\`\`\`dart
final weekDays = generateWeekDays();

for (var day in weekDays) {
  print('\${DateFormat('EEE, MMM d').format(day)}');
}
// Output:
// Mon, Jan 15
// Tue, Jan 16
// ...
\`\`\`

## 9. Performance Tips

### Const Constructors
\`\`\`dart
// Use const where possible
const DayCard(
  date: DateTime(2024, 1, 15),
)
\`\`\`

### Avoid Unnecessary Rebuilds
\`\`\`dart
// Good: Only rebuild when needed
PageView.builder(
  // Builder only calls when page is visible
  itemBuilder: (context, page) => buildPage(page),
)

// Bad: Building all pages upfront
PageView(
  children: List.generate(1000, (i) => buildPage(i)),
)
\`\`\`

## 10. Error Handling

### Safe Date Parsing
\`\`\`dart
DateTime? parseDate(String dateString) {
  try {
    return DateTime.parse(dateString);
  } catch (e) {
    print('Error parsing date: \$e');
    return null;
  }
}
\`\`\`

### Boundary Checks
\`\`\`dart
List<DateTime> generateWeekDays({DateTime? startDate}) {
  final start = startDate ?? DateTime.now();
  
  // Normalize to avoid time-of-day issues
  final normalizedStart = DateTime(start.year, start.month, start.day);
  
  return List.generate(7, (index) {
    return normalizedStart.add(Duration(days: index));
  });
}
\`\`\`
