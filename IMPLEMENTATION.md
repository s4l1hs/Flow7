# Flutter Main Calendar View Implementation

This document describes the implementation of the 7-day calendar view feature for Flow7.

## Overview

The implementation provides a horizontally scrollable calendar view that displays 7 days at a time. Users can swipe left/right to navigate between weeks.

## Project Structure

```
Flow7/
├── lib/
│   ├── main.dart                    # App entry point
│   ├── screens/
│   │   └── main_screen.dart        # Main calendar view screen
│   ├── widgets/
│   │   └── day_card.dart           # Individual day card component
│   └── utils/
│       └── date_utils.dart         # Date generation utilities
├── test/
│   ├── date_utils_test.dart        # Tests for date utilities
│   └── day_card_test.dart          # Tests for DayCard widget
└── pubspec.yaml                     # Project dependencies
```

## Components

### 1. Date Utilities (`lib/utils/date_utils.dart`)

Provides utility functions for date operations:

- **`generateWeekDays({DateTime? startDate})`**: Generates an array of 7 consecutive days starting from the given date (defaults to today). Returns a list of DateTime objects normalized to midnight.

- **`getWeekStart(DateTime date)`**: Returns the start of the week (Monday) for any given date. Useful for ensuring weeks always start on Monday.

### 2. DayCard Widget (`lib/widgets/day_card.dart`)

A card component that displays a single day:

- Shows the day of the week (e.g., Mon, Tue, Wed)
- Shows the date number (e.g., 1, 15, 28)
- Highlights the current day with:
  - Higher elevation (4.0 vs 1.0)
  - Different background color (primaryContainer)
  - Bold text styling

### 3. Main Screen (`lib/screens/main_screen.dart`)

The main calendar view screen with the following features:

- **Horizontal Scrolling**: Uses `PageView.builder` to enable smooth horizontal scrolling between weeks
- **Week Navigation**: Users can swipe left to view future weeks and right to view past weeks
- **Week Header**: Displays the date range for the current week (e.g., "Jan 15 - 21, 2024")
- **7-Day View**: Shows 7 DayCard widgets in a vertical list for each week
- **State Management**: Tracks the current week's start date using Flutter's StatefulWidget
- **Infinite Scrolling**: Supports scrolling through multiple weeks in both directions

## Key Features

### Date Generation

The date generation utility ensures:
- All dates are normalized to midnight (00:00:00) to avoid time-of-day issues
- Handles month boundaries correctly (e.g., Jan 31 to Feb 1)
- Handles year boundaries correctly (e.g., Dec 31 to Jan 1)

### Horizontal Scrolling

The PageView implementation:
- Starts at a high page number (10000) to allow backward scrolling
- Calculates week offsets from the initial page
- Updates the current week state on page changes
- Provides smooth, gesture-based navigation

### UI Components

Each DayCard:
- Uses Material Design 3 theming
- Adapts colors based on the current theme
- Highlights today's date for easy identification
- Has consistent spacing and padding

## Running the App

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Dart SDK (3.0.0 or higher)

### Installation

1. Install dependencies:
   ```bash
   flutter pub get
   ```

2. Run the app:
   ```bash
   flutter run
   ```

### Running Tests

Run all tests:
```bash
flutter test
```

Run specific test files:
```bash
flutter test test/date_utils_test.dart
flutter test test/day_card_test.dart
```

## Testing

### Date Utils Tests

The test suite covers:
- Generating 7 days from a given start date
- Defaulting to today when no date is provided
- Date normalization to midnight
- Finding the start of the week (Monday)
- Handling month and year boundaries

### DayCard Widget Tests

The test suite covers:
- Displaying day of week and date number
- Highlighting today with different styling
- Using normal styling for non-today dates

## Usage Example

The main screen is automatically displayed when the app launches. Users can:

1. **View Current Week**: The app opens showing the current week (Monday-Sunday)
2. **Navigate to Future Weeks**: Swipe left to view upcoming weeks
3. **Navigate to Past Weeks**: Swipe right to view previous weeks
4. **Identify Today**: The current day is highlighted with a different color and elevation

## Dependencies

- **flutter**: Core Flutter framework
- **intl**: ^0.18.0 - For date formatting (e.g., "Mon", "Tue", day numbers)
- **flutter_test**: For widget and unit testing
- **flutter_lints**: For code quality and style enforcement

## Future Enhancements

Potential improvements for this calendar view:

1. Add ability to tap on a day to view/add tasks for that day
2. Display task indicators on each day card
3. Add month/year navigation controls
4. Support for different week start days (Sunday vs Monday)
5. Customizable date ranges (beyond 7 days)
6. Integration with calendar data/events
7. Accessibility improvements (screen reader support, high contrast mode)

## Architecture Notes

The implementation follows Flutter best practices:

- **Separation of Concerns**: UI components, utilities, and screens are in separate directories
- **Widget Composition**: Small, reusable widgets (DayCard) compose into larger screens
- **State Management**: Uses StatefulWidget for local state management
- **Testability**: Pure functions in utilities make testing straightforward
- **Material Design**: Uses Material 3 theming for consistent, modern UI

## Performance Considerations

- **Lazy Loading**: PageView.builder only builds visible pages, not all possible weeks
- **Efficient Updates**: Only rebuilds affected widgets when state changes
- **Date Normalization**: Normalizes dates once during generation to avoid repeated calculations
- **Controller Disposal**: Properly disposes of PageController to prevent memory leaks
