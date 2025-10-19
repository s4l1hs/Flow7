# Changelog

All notable changes to Flow7 will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-10-19

### 🎉 Initial Release

This is the first release of Flow7 - Weekly Flow Mobile Planner!

### ✨ Added

#### Frontend (Flutter)
- **7-Day Horizontal Scrollable Calendar**
  - Infinite horizontal scrolling through weeks
  - Visual indicators for today, selected date, and locked dates
  - PageView implementation for smooth navigation
  - Tier badge showing current subscription plan
  - Lock icons for dates beyond tier limits

- **Event Management UI**
  - EventList widget for displaying daily events
  - EventDialog for creating/editing events
  - Event cards with edit and delete actions
  - Time picker integration
  - Form validation

- **Planner Screen**
  - Main screen combining all components
  - Date selection and navigation
  - Event CRUD operations
  - Success/error feedback with SnackBars
  - Tier information dialog

- **Data Models**
  - Event model with JSON serialization
  - UserTier enum with tier limits (14/30/60 days)
  - Type-safe models throughout

- **API Service**
  - REST API client with HTTP package
  - Client-side date validation
  - Tier-based access control
  - Proper error handling

#### Backend (Python/Flask)
- **REST API Endpoints**
  - `POST /events` - Create new event with tier validation
  - `GET /events` - Get events in date range
  - `GET /events/:id` - Get single event
  - `PUT /events/:id` - Update event with tier validation
  - `DELETE /events/:id` - Delete event
  - `GET /tier-info` - Get tier limits
  - `GET /health` - Health check

- **Firestore Integration**
  - FirestoreService class for database operations
  - CRUD operations for events
  - Date range queries
  - Automatic timestamps

- **Tier System**
  - UserTier enum (FREE, PRO, ULTRA)
  - Date range validation based on tier
  - Server-side enforcement of limits
  - Proper error messages with tier information

- **Security & Validation**
  - Request validation
  - Date range checks
  - CORS configuration
  - Error handling throughout

#### Documentation
- **README.md** - Project overview and setup instructions
- **QUICKSTART.md** - 5-minute setup guide
- **ARCHITECTURE.md** - System design and data flow
- **UI_GUIDE.md** - UI components and interactions
- **DEPLOYMENT.md** - Production deployment guide
- **CONTRIBUTING.md** - Contribution guidelines
- **SUMMARY.md** - Complete project summary
- **backend/API.md** - API documentation with examples

#### Testing & Tools
- **Backend Unit Tests** - 6 tests for tier validation
- **Demo Script** - Python script to test tier limits
- **API Test Script** - Shell script with curl examples
- **Setup Script** - Automated setup for development

### 🎯 Features

#### Freemium Tier Limits
- **FREE Tier**: 14 days future planning
- **PRO Tier**: 30 days future planning
- **ULTRA Tier**: 60 days future planning
- Dual validation (client + server)
- Visual feedback in UI

#### Event Management
- Create events with title, start time, end time
- Edit existing events
- Delete events with confirmation
- View events sorted by date and time
- Automatic date association

#### User Experience
- Smooth animations and transitions
- Clear error messages
- Visual feedback for all actions
- Intuitive navigation
- Responsive design

### 📦 Dependencies

#### Flutter
- flutter: SDK
- cupertino_icons: ^1.0.2
- http: ^1.1.0
- intl: ^0.18.1
- provider: ^6.0.5

#### Python
- flask: 3.0.0
- firebase-admin: 6.3.0
- flask-cors: 4.0.0
- python-dotenv: 1.0.0

### 🔧 Technical Details

#### Data Model
```json
{
  "id": "string",
  "date": "ISO 8601 datetime",
  "start_time": "HH:MM",
  "end_time": "HH:MM",
  "title": "string"
}
```

#### Architecture
- Flutter frontend with Material Design
- Python/Flask REST API backend
- Google Cloud Firestore database
- Client-server tier validation

### 📝 Known Limitations

- Requires Firebase/Firestore setup
- No user authentication (planned for v1.1)
- No recurring events (planned for v1.2)
- No offline support (planned for v1.3)

### 🙏 Credits

- Initial implementation by the Flow7 team
- Built with Flutter and Python/Flask
- Uses Google Cloud Firestore

---

## [Unreleased]

### Planned Features
- User authentication with Firebase Auth
- Recurring events support
- Event categories and colors
- Push notifications
- Offline support with local database
- Calendar sync (Google, Apple)
- Dark mode theme
- Multiple language support

---

## Release Notes Format

### Added
- New features and capabilities

### Changed
- Changes to existing functionality

### Deprecated
- Features that will be removed in future releases

### Removed
- Features that have been removed

### Fixed
- Bug fixes

### Security
- Security improvements and fixes

---

**Note**: This changelog will be updated with each release. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute to Flow7.
