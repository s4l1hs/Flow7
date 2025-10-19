# Flow7 UI Guide

## Main Screen Components

### 1. App Bar
```
┌─────────────────────────────────────────────┐
│  Flow7 - Weekly Planner              (i)    │
└─────────────────────────────────────────────┘
```
- **Title**: "Flow7 - Weekly Planner"
- **Info button**: Tap to see tier information and upgrade options

### 2. Tier Indicator
```
┌─────────────────────────────────────────────┐
│  Plan up to 14 days ahead          [FREE]   │
└─────────────────────────────────────────────┘
```
- Shows current tier and planning limit
- Color-coded:
  - FREE: Grey
  - PRO: Blue
  - ULTRA: Purple

### 3. 7-Day Horizontal Calendar
```
┌─────────────────────────────────────────────┐
│  Mon  Tue  Wed  Thu  Fri  Sat  Sun          │
│   1    2    3    4    5    6    7           │
│              ▓                               │  (selected)
│                              🔒   🔒          │  (locked)
└─────────────────────────────────────────────┘
```

**Navigation:**
- Swipe left/right to navigate through weeks
- Tap a date to select it
- Unlimited scrolling in both directions

**Visual Indicators:**
- **Today**: Light blue background
- **Selected**: Blue background with white text
- **Locked**: Red border with lock icon (beyond tier limit)
- **Normal**: Grey border

**Date States:**
```
┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐
│ Mon │  │ Tue │  │ Wed │  │ Thu │
│  15 │  │  16 │  │  17 │  │  18 │
│     │  │  ▓  │  │     │  │  🔒 │
└─────┘  └─────┘  └─────┘  └─────┘
Normal   Selected  Today    Locked
```

### 4. Selected Date Header
```
┌─────────────────────────────────────────────┐
│  Wednesday, January 17, 2024           +    │
└─────────────────────────────────────────────┘
```
- Full date display in readable format
- **+ button**: Create new event (only shown for unlocked dates)

### 5. Event List

**When events exist:**
```
┌─────────────────────────────────────────────┐
│ │ Team Meeting                        ✏️  🗑️ │
│ │ ⏰ 09:00 - 10:00                           │
├─────────────────────────────────────────────┤
│ │ Lunch Break                         ✏️  🗑️ │
│ │ ⏰ 12:00 - 13:00                           │
├─────────────────────────────────────────────┤
│ │ Project Review                      ✏️  🗑️ │
│ │ ⏰ 14:00 - 15:30                           │
└─────────────────────────────────────────────┘
```

**When no events:**
```
┌─────────────────────────────────────────────┐
│                                              │
│              📅                              │
│       No events for this day                 │
│                                              │
└─────────────────────────────────────────────┘
```

### 6. Event Card Details
```
┌─────────────────────────────────────────────┐
│ ▌ Title: Team Meeting                       │
│ │ ⏰ Time: 09:00 - 10:00                     │
│ │                                  ✏️  🗑️    │
└─────────────────────────────────────────────┘
```
- **Blue bar**: Visual indicator on the left
- **Title**: Event name (bold)
- **Time**: Start and end time with clock icon
- **Edit button** (✏️): Tap to modify event
- **Delete button** (🗑️): Tap to delete event (with confirmation)

## Dialogs and Interactions

### Create/Edit Event Dialog
```
┌─────────────────────────────────────────────┐
│  New Event                           ×       │
├─────────────────────────────────────────────┤
│  Title                                       │
│  ┌───────────────────────────────────────┐  │
│  │ [Enter event title]                   │  │
│  └───────────────────────────────────────┘  │
│                                              │
│  Start Time                                  │
│  ┌───────────────────────────────────────┐  │
│  │ 09:00                              ⏰ │  │
│  └───────────────────────────────────────┘  │
│                                              │
│  End Time                                    │
│  ┌───────────────────────────────────────┐  │
│  │ 10:00                              ⏰ │  │
│  └───────────────────────────────────────┘  │
│                                              │
│              [Cancel]    [Create]            │
└─────────────────────────────────────────────┘
```

**Features:**
- Title: Required text field
- Start/End Time: Tap to open time picker
- Cancel: Dismiss without saving
- Create/Update: Save event

### Delete Confirmation
```
┌─────────────────────────────────────────────┐
│  Delete Event                                │
├─────────────────────────────────────────────┤
│  Are you sure you want to delete             │
│  "Team Meeting"?                             │
│                                              │
│              [Cancel]    [Delete]            │
└─────────────────────────────────────────────┘
```

### Tier Information Dialog
```
┌─────────────────────────────────────────────┐
│  Subscription Tier                    ×      │
├─────────────────────────────────────────────┤
│  Current Plan: FREE                          │
│                                              │
│  You can plan up to 14 days in the future.  │
│                                              │
│  Upgrade to access more planning days:      │
│                                              │
│  ✅ FREE: 14 days                            │
│  ○  PRO: 30 days                             │
│  ○  ULTRA: 60 days                           │
│                                              │
│                         [Close]              │
└─────────────────────────────────────────────┘
```

### Error Messages

**When tapping locked date:**
```
┌─────────────────────────────────────────────┐
│  Date is outside your FREE plan limit        │
│  (14 days)                                   │
└─────────────────────────────────────────────┘
```
*Appears as snackbar at bottom of screen*

**When API error occurs:**
```
┌─────────────────────────────────────────────┐
│  Error creating event: Date is outside      │
│  allowed range for FREE tier                 │
└─────────────────────────────────────────────┘
```
*Red snackbar indicating error*

**When operation succeeds:**
```
┌─────────────────────────────────────────────┐
│  ✓ Event created successfully                │
└─────────────────────────────────────────────┘
```
*Green snackbar indicating success*

## User Interactions Summary

### Creating an Event
1. Navigate to desired date using calendar
2. Tap the **+** button
3. Fill in event details:
   - Enter title
   - Select start time
   - Select end time
4. Tap **Create**
5. See success message
6. Event appears in list

### Editing an Event
1. Find event in list
2. Tap **✏️ Edit** button
3. Modify details
4. Tap **Update**
5. See success message
6. Changes appear immediately

### Deleting an Event
1. Find event in list
2. Tap **🗑️ Delete** button
3. Confirm deletion in dialog
4. See success message
5. Event disappears from list

### Navigating Calendar
- **Swipe left**: View next week
- **Swipe right**: View previous week
- **Tap date**: Select date and load events
- **Tap locked date**: See tier limit message

### Checking Tier Info
1. Tap **(i)** button in app bar
2. View current tier and limits
3. See upgrade options
4. Close dialog

## Color Scheme

### Tier Colors
- **FREE**: Grey (#808080)
- **PRO**: Blue (#2196F3)
- **ULTRA**: Purple (#9C27B0)

### UI Colors
- **Primary**: Blue (#2196F3)
- **Success**: Green (#4CAF50)
- **Error**: Red (#F44336)
- **Background**: White (#FFFFFF)
- **Text**: Black (#000000)
- **Secondary Text**: Grey (#757575)

## Accessibility Features

- **Large touch targets**: All interactive elements are at least 44x44 points
- **Clear visual feedback**: Selected states, hover states
- **Error messages**: Clear, specific error descriptions
- **Time picker**: Standard system time picker (accessible by default)
- **Scrollable lists**: Support for assistive technologies

## Responsive Design

The UI adapts to:
- Different screen sizes (phones, tablets)
- Orientation changes (portrait, landscape)
- Various screen densities
- Different platform styles (iOS, Android, Web)
