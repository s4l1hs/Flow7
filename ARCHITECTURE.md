# Flow7 Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Mobile App                        │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Planner Screen (UI)                       │ │
│  │  - 7-Day Horizontal Scrollable Calendar               │ │
│  │  - Event List View                                     │ │
│  │  - Event Dialog (CRUD)                                 │ │
│  └────────────────────────────────────────────────────────┘ │
│                          ▼                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              API Service Layer                         │ │
│  │  - HTTP Client (REST API)                             │ │
│  │  - Client-side Tier Validation                        │ │
│  │  - Date Range Enforcement                             │ │
│  └────────────────────────────────────────────────────────┘ │
│                          ▼                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                 Data Models                            │ │
│  │  - Event: {date, start_time, end_time, title}         │ │
│  │  - UserTier: FREE (14d) | PRO (30d) | ULTRA (60d)     │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                          ▼
                    HTTP/REST API
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   Python/Flask Backend                       │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                  API Routes                            │ │
│  │  - POST   /events         (Create)                    │ │
│  │  - GET    /events         (Read All)                  │ │
│  │  - GET    /events/:id     (Read One)                  │ │
│  │  - PUT    /events/:id     (Update)                    │ │
│  │  - DELETE /events/:id     (Delete)                    │ │
│  │  - GET    /tier-info      (Tier Info)                 │ │
│  └────────────────────────────────────────────────────────┘ │
│                          ▼                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │            Tier Validation Middleware                  │ │
│  │  - Extract X-User-Tier header                         │ │
│  │  - Validate date ranges                               │ │
│  │  - Enforce tier limits                                │ │
│  └────────────────────────────────────────────────────────┘ │
│                          ▼                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Firestore Service                         │ │
│  │  - CRUD operations                                     │ │
│  │  - Date range queries                                  │ │
│  │  - Collection: events                                  │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  Google Cloud Firestore                      │
│  Collection: events                                          │
│  Document Structure:                                         │
│  {                                                           │
│    id: string                                               │
│    date: string (ISO 8601)                                  │
│    start_time: string (HH:MM)                               │
│    end_time: string (HH:MM)                                 │
│    title: string                                            │
│    created_at: timestamp                                    │
│    updated_at: timestamp                                    │
│  }                                                          │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

### Create Event Flow

1. User taps "+" button in Flutter app
2. EventDialog opens with form
3. User fills in title, start_time, end_time
4. On submit:
   - ApiService validates date against user tier
   - If valid: HTTP POST to `/events` with X-User-Tier header
   - Backend validates date again (server-side validation)
   - If valid: Firestore creates document
   - Response returns to Flutter with event ID
   - UI refreshes to show new event

### Date Range Enforcement

**Client-side (Flutter):**
- WeeklyCalendar widget checks `isDateAllowed()`
- Dates beyond tier limit show lock icon
- Tapping locked date shows tier upgrade message
- ApiService validates before API calls

**Server-side (Python):**
- `validate_event_date()` function checks date
- Returns 403 Forbidden if date exceeds tier limit
- Error message includes tier name and max days
- Prevents unauthorized future planning

## Freemium Tier Limits

| Tier  | Max Days | Enforcement Points |
|-------|----------|-------------------|
| FREE  | 14       | Flutter + Python  |
| PRO   | 30       | Flutter + Python  |
| ULTRA | 60       | Flutter + Python  |

## Key Components

### Flutter Widgets

1. **WeeklyCalendar**: Horizontal scrollable 7-day view with PageView
   - Shows current week
   - Swipe left/right to navigate
   - Visual indicators for locked dates
   - Tier badge showing current plan

2. **EventList**: Displays events for selected date
   - Empty state when no events
   - Swipe actions or buttons for edit/delete
   - Time indicators

3. **EventDialog**: Modal for CRUD operations
   - Form validation
   - Time picker integration
   - Create/Update modes

### Backend Services

1. **FirestoreService**: Database abstraction layer
   - CRUD operations
   - Query builders
   - Error handling

2. **Tier Validation**: Centralized date validation
   - UserTier enum
   - `validate_date_range()` function
   - `get_max_allowed_date()` helper

## Security Considerations

1. **Tier Validation**: Enforced on both client and server
2. **API Headers**: X-User-Tier header for tier identification
3. **Future Enhancement**: Add authentication/authorization
4. **Firebase Rules**: Should be configured to restrict access

## Scalability

- Firestore provides automatic scaling
- Flask can be deployed to Cloud Run or App Engine
- Flutter compiles to native code for performance
- API can be cached with CDN for static tier info

## Future Enhancements

1. User authentication (Firebase Auth)
2. Event categories/colors
3. Recurring events
4. Event reminders/notifications
5. Calendar sync (Google Calendar, Apple Calendar)
6. Team/shared calendars
7. Analytics and insights
8. Offline support with local database
