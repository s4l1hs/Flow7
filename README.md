# Flow7 - Weekly Flow Mobile Planner

Flow7 is a mobile application that allows users to plan their schedules with a beautiful 7-day scrollable calendar view. The app implements freemium planning limits based on subscription tiers.

## Features

- **7-Day Horizontal Scrollable Calendar**: Navigate through weeks with an intuitive horizontal scroll view
- **CRUD Event Management**: Create, Read, Update, and Delete events with ease
- **Freemium Tier System**:
  - **FREE**: Plan up to 14 days in the future
  - **PRO**: Plan up to 30 days in the future
  - **ULTRA**: Plan up to 60 days in the future
- **Event Data Model**: Each event includes date, start_time, end_time, and title
- **Backend API**: Python/Flask backend with Firestore database
- **Date Range Enforcement**: API-level validation based on user tier

## Tech Stack

### Frontend
- **Flutter**: Cross-platform mobile app framework
- **Dart**: Programming language
- **Material Design**: UI/UX framework

### Backend
- **Python**: Programming language
- **Flask**: Web framework
- **Firestore**: NoSQL database (Google Cloud)
- **Flask-CORS**: Cross-Origin Resource Sharing support

## Project Structure

```
Flow7/
├── flutter_app/           # Flutter mobile application
│   ├── lib/
│   │   ├── models/        # Data models (Event, UserTier)
│   │   ├── screens/       # UI screens (PlannerScreen)
│   │   ├── widgets/       # Reusable widgets (WeeklyCalendar, EventList, EventDialog)
│   │   ├── services/      # API service layer
│   │   └── main.dart      # App entry point
│   └── pubspec.yaml       # Flutter dependencies
│
└── backend/               # Python/Flask API
    ├── app.py             # Flask application and routes
    ├── models.py          # User tier models and validation
    ├── firestore_service.py  # Firestore database operations
    ├── requirements.txt   # Python dependencies
    └── API.md            # API documentation
```

## Getting Started

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Python 3.8 or higher
- Firebase/Firestore account (for database)
- Firebase service account key (serviceAccountKey.json)

### Backend Setup

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```

2. Install Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Set up Firestore:
   - Create a Firebase project at https://console.firebase.google.com/
   - Enable Firestore Database
   - Download the service account key JSON file
   - Save it as `serviceAccountKey.json` in the backend directory

4. Create `.env` file (optional):
   ```bash
   cp .env.example .env
   ```

5. Run the Flask server:
   ```bash
   python app.py
   ```

The API will be available at `http://localhost:8000`

### Flutter App Setup

1. Navigate to the flutter_app directory:
   ```bash
   cd flutter_app
   ```

2. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```

3. Update the API base URL in `lib/main.dart` if needed:
   ```dart
   apiBaseUrl: 'http://localhost:8000',  // Change to your backend URL
   ```

4. Run the app:
   ```bash
   flutter run
   ```

## Usage

### Changing User Tier

To test different subscription tiers, modify the `userTier` parameter in `lib/main.dart`:

```dart
PlannerScreen(
  userTier: UserTier.free,  // Change to UserTier.pro or UserTier.ultra
  apiBaseUrl: 'http://localhost:8000',
)
```

### API Endpoints

See [backend/API.md](backend/API.md) for detailed API documentation.

## Freemium Planning Limits

The application enforces planning limits both in the Flutter frontend and Python backend:

| Tier  | Max Future Days | Color  |
|-------|----------------|--------|
| FREE  | 14 days        | Grey   |
| PRO   | 30 days        | Blue   |
| ULTRA | 60 days        | Purple |

- **Frontend**: Visual indicators show locked dates beyond the user's tier limit
- **Backend**: API validates event dates and returns 403 Forbidden for dates outside the allowed range

## Development

### Running Tests

Backend tests (if implemented):
```bash
cd backend
pytest
```

Flutter tests:
```bash
cd flutter_app
flutter test
```

## License

This project is licensed under the MIT License.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
