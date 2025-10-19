# Flow7

Flow7 is an application that allows users to plan their programs for the next 2/4/8 weeks according to their current plans. Flow7 helps users live an organized and planned life.

## Features

### ✅ 7-Day Calendar View
- Horizontally scrollable calendar showing 7 days at a time
- Swipe left/right to navigate between weeks
- Today's date is highlighted for easy identification
- Week date range displayed at the top
- Clean, Material Design 3 interface

## Quick Start

### Prerequisites
- Flutter SDK 3.0.0 or higher
- Dart SDK 3.0.0 or higher

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/s4l1hs/Flow7.git
   cd Flow7
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

### Running Tests

```bash
# Run all tests
flutter test

# Run specific test files
flutter test test/date_utils_test.dart
flutter test test/day_card_test.dart
```

## Project Structure

```
Flow7/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── screens/
│   │   └── main_screen.dart     # Main calendar view
│   ├── widgets/
│   │   └── day_card.dart        # Day card component
│   └── utils/
│       └── date_utils.dart      # Date utilities
├── test/
│   ├── date_utils_test.dart     # Unit tests
│   └── day_card_test.dart       # Widget tests
└── pubspec.yaml                  # Dependencies
```

## Documentation

- **[IMPLEMENTATION.md](IMPLEMENTATION.md)** - Detailed implementation guide
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Architecture and design decisions

## Usage

1. **View Current Week**: The app opens showing the current week starting from Monday
2. **Navigate Forward**: Swipe left to view future weeks
3. **Navigate Backward**: Swipe right to view past weeks
4. **Identify Today**: The current day is highlighted with a blue background

## Development

### Verify Implementation

Run the verification script to check all components:

```bash
./verify_implementation.sh
```

### Code Style

The project uses Flutter lints for code quality:

```bash
flutter analyze
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Roadmap

- [x] 7-day horizontal scrolling calendar view
- [ ] Task/event management for each day
- [ ] 2/4/8 week planning views
- [ ] Task categories and priorities
- [ ] Recurring tasks support
- [ ] Data persistence
- [ ] Cloud sync
- [ ] Notifications and reminders
