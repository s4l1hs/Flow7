# UI Layout and Design

## Main Screen Layout

```
┌─────────────────────────────────────────┐
│  Flow7                              ☰   │  ← AppBar
├─────────────────────────────────────────┤
│                                         │
│  Jan 15 - 21, 2024                     │  ← Week Header
│                                         │
│  ┌───────────────────────────────────┐ │
│  │  Mon                              │ │
│  │  15                               │ │  ← DayCard
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │  Tue                              │ │
│  │  16                               │ │  ← DayCard
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │  Wed                              │ │
│  │  17                               │ │  ← DayCard (Today - Highlighted)
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │  Thu                              │ │
│  │  18                               │ │  ← DayCard
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │  Fri                              │ │
│  │  19                               │ │  ← DayCard
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │  Sat                              │ │
│  │  20                               │ │  ← DayCard
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │  Sun                              │ │
│  │  21                               │ │  ← DayCard
│  └───────────────────────────────────┘ │
│                                         │
└─────────────────────────────────────────┘

← Swipe left/right to navigate weeks →
```

## DayCard Component

### Normal Day
```
┌───────────────────────┐
│                       │
│       Mon             │  ← Day of week (14pt, normal weight)
│                       │
│        15             │  ← Date number (24pt, bold)
│                       │
└───────────────────────┘
```
- Elevation: 1.0
- Background: Surface color
- Text: OnSurface color

### Today (Highlighted)
```
┌═══════════════════════┐
║                       ║
║       Wed             ║  ← Day of week (14pt, bold)
║                       ║
║        17             ║  ← Date number (24pt, bold)
║                       ║
└═══════════════════════┘
```
- Elevation: 4.0 (more shadow)
- Background: Primary Container (light blue)
- Text: OnPrimaryContainer (dark blue)
- Border: Thicker visual weight

## Color Scheme (Material 3)

### Light Theme
- **Primary**: Blue (#2196F3)
- **Surface**: White (#FFFFFF)
- **OnSurface**: Black (#000000)
- **PrimaryContainer**: Light Blue (#BBDEFB)
- **OnPrimaryContainer**: Dark Blue (#0D47A1)

### Dark Theme Support
- Automatically adapts to system theme
- Uses Material 3 dark color scheme

## Spacing and Padding

```
MainScreen Padding:     16px all around
Week Header Padding:    16px vertical
DayCard Margin:         4px horizontal
DayCard Padding:        12px all around
Text Spacing:           8px between day name and number
```

## Typography

```
Week Header:    headlineSmall (24pt, medium weight)
Day of Week:    14pt
Date Number:    24pt, bold
```

## Gestures

```
← Swipe Left  = Next Week (Future)
→ Swipe Right = Previous Week (Past)
```

## Page Transitions

- Smooth, native page sliding animation
- Physics-based scrolling with bounce effect
- Snap to page boundaries

## Responsive Design

The layout adapts to different screen sizes:

- **Phone Portrait**: Full width, scrollable list
- **Phone Landscape**: Same layout, more visible at once
- **Tablet**: Wider cards with more spacing
- **Large Screens**: Maximum width constraint (if implemented)

## Animation States

1. **Page Transition**: Slide left/right
2. **Card Elevation**: Subtle shadow change on today's card
3. **State Updates**: Smooth week header text updates

## Accessibility

- Minimum touch target size: 48x48dp
- Contrast ratios meet WCAG AA standards
- Semantic labels for screen readers
- Supports text scaling
- High contrast theme support
