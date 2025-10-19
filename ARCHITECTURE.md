# Flow7 Calendar View Architecture

## Component Hierarchy

```
Flow7App (MaterialApp)
    └── MainScreen (StatefulWidget)
        └── Scaffold
            ├── AppBar
            │   └── Title: "Flow7"
            └── PageView.builder (Horizontal Scrolling)
                └── Page (for each week)
                    └── Column
                        ├── Week Header (Text)
                        │   └── Date Range (e.g., "Jan 15 - 21, 2024")
                        └── ListView.builder (Vertical Scrolling)
                            └── DayCard × 7
                                └── Card
                                    ├── Day of Week (e.g., "Mon")
                                    └── Date Number (e.g., "15")
```

## Data Flow

```
User Swipes ───────────────────────────────────────┐
                                                    │
                                                    ▼
                                        PageView.onPageChanged
                                                    │
                                                    ▼
                                        setState (update _currentWeekStart)
                                                    │
                                                    ▼
                                        _getWeekStartForPage(page)
                                                    │
                                                    ▼
                                        date_utils.generateWeekDays(weekStart)
                                                    │
                                                    ▼
                                        Build 7 DayCard widgets
                                                    │
                                                    ▼
                                        Display updated week view
```

## State Management

### MainScreen State
- `_pageController`: Controls PageView scrolling
- `_currentWeekStart`: Tracks the Monday of the current visible week
- `_initialPage`: Set to 10000 to allow backward/forward scrolling

### Page Calculation
```
currentPage = 10000 (initial)
offset = currentPage - initialPage
weekStartDate = _currentWeekStart + (offset * 7 days)
```

## Key Functions

### Date Utilities (`lib/utils/date_utils.dart`)

#### `generateWeekDays({DateTime? startDate})`
- **Input**: Optional startDate (defaults to today)
- **Process**: 
  1. Normalize date to midnight
  2. Generate 7 consecutive dates
- **Output**: List<DateTime> with 7 dates

#### `getWeekStart(DateTime date)`
- **Input**: Any date
- **Process**:
  1. Normalize date to midnight
  2. Calculate days to subtract to get to Monday
- **Output**: DateTime for Monday of that week

### Main Screen (`lib/screens/main_screen.dart`)

#### `_getWeekStartForPage(int page)`
- **Input**: Page index
- **Process**: Calculate week offset from initial page
- **Output**: DateTime for that week's start

#### `_getWeekRangeText(List<DateTime> weekDays)`
- **Input**: List of 7 dates
- **Process**: Format start and end dates
- **Output**: String like "Jan 15 - 21, 2024"

## Theming

The implementation uses Material Design 3 theming:

- **DayCard (Normal)**
  - Elevation: 1.0
  - Color: Default surface color
  - Text: OnSurface color

- **DayCard (Today)**
  - Elevation: 4.0
  - Color: PrimaryContainer
  - Text: OnPrimaryContainer (bold)

## Testing Strategy

### Unit Tests (`test/date_utils_test.dart`)
- Generate 7 days from specific date
- Default to today
- Date normalization
- Week start calculation
- Month/year boundary handling

### Widget Tests (`test/day_card_test.dart`)
- Display day name and number
- Today highlighting (elevation, color)
- Normal day styling

### Integration Testing (Manual)
1. Open app → Should show current week
2. Swipe left → Should show next week
3. Swipe right → Should show previous week
4. Check today highlighting → Should be visible

## Performance Optimizations

1. **Lazy Loading**: PageView.builder creates pages on-demand
2. **Date Normalization**: Done once per date to avoid repeated calculations
3. **Const Constructors**: Widgets use const where possible
4. **Efficient Rebuilds**: Only affected widgets rebuild on state changes
5. **Resource Cleanup**: PageController properly disposed

## Accessibility Features

- Semantic labels via Material widgets
- High contrast support via theme
- Text scaling supported
- Touch targets meet minimum size requirements

## Error Handling

- Null safety enabled (SDK >= 3.0.0)
- Defensive date normalization
- Graceful handling of edge cases (month/year boundaries)
