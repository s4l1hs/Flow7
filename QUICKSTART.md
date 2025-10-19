# Quick Start Guide

## For Users Who Want to Run Flow7 Immediately

### Option 1: Automated Setup (Recommended)

```bash
# Clone the repository
git clone https://github.com/s4l1hs/Flow7.git
cd Flow7

# Run the setup script
chmod +x setup.sh
./setup.sh
```

### Option 2: Manual Setup

#### Backend Setup (5 minutes)

1. **Install Python dependencies:**
   ```bash
   cd backend
   pip install -r requirements.txt
   ```

2. **Set up Firebase/Firestore:**
   - Go to https://console.firebase.google.com/
   - Create a new project
   - Enable Firestore Database
   - Go to Project Settings > Service Accounts
   - Click "Generate New Private Key"
   - Save the file as `backend/serviceAccountKey.json`

3. **Start the backend server:**
   ```bash
   python app.py
   ```
   
   Server will start at `http://localhost:8000`

#### Flutter App Setup (5 minutes)

1. **Install Flutter:**
   - Follow instructions at https://flutter.dev/docs/get-started/install
   - Verify installation: `flutter doctor`

2. **Install dependencies:**
   ```bash
   cd flutter_app
   flutter pub get
   ```

3. **Run the app:**
   ```bash
   flutter run
   ```
   
   Choose your target device (iOS Simulator, Android Emulator, or Chrome)

## Testing Different Tiers

To test different subscription tiers, edit `flutter_app/lib/main.dart`:

```dart
PlannerScreen(
  userTier: UserTier.free,  // Change to: UserTier.pro or UserTier.ultra
  apiBaseUrl: 'http://localhost:8000',
)
```

### Tier Comparison

| Feature | FREE | PRO | ULTRA |
|---------|------|-----|-------|
| Future Planning | 14 days | 30 days | 60 days |
| Event CRUD | ✅ | ✅ | ✅ |
| 7-Day Calendar | ✅ | ✅ | ✅ |
| API Access | ✅ | ✅ | ✅ |

## Testing the Backend API

Run the demo script to test tier enforcement:

```bash
cd backend
python demo.py
```

This will:
- Test all three tiers (FREE, PRO, ULTRA)
- Verify date range enforcement
- Test CRUD operations
- Display results in the terminal

## Expected Behavior

### FREE Tier (14 days)
- ✅ Can create events from today to 14 days in the future
- ❌ Cannot create events beyond 14 days
- 🔒 Days 15+ show with lock icon in calendar

### PRO Tier (30 days)
- ✅ Can create events from today to 30 days in the future
- ❌ Cannot create events beyond 30 days
- 🔒 Days 31+ show with lock icon in calendar

### ULTRA Tier (60 days)
- ✅ Can create events from today to 60 days in the future
- ❌ Cannot create events beyond 60 days
- 🔒 Days 61+ show with lock icon in calendar

## Troubleshooting

### Backend Issues

**Problem:** `ModuleNotFoundError: No module named 'flask'`
```bash
pip install -r backend/requirements.txt
```

**Problem:** `Firebase Admin SDK initialization error`
- Ensure `serviceAccountKey.json` exists in `backend/` directory
- Check that the file is valid JSON
- Verify Firebase project is set up correctly

**Problem:** Port 8000 already in use
```bash
# Change port in backend/app.py or .env
PORT=8080 python app.py
```

### Flutter Issues

**Problem:** `flutter: command not found`
- Install Flutter SDK: https://flutter.dev/docs/get-started/install
- Add Flutter to PATH

**Problem:** `No devices found`
- Start an emulator: `flutter emulators --launch <emulator_id>`
- Or run on web: `flutter run -d chrome`

**Problem:** Network error when creating events
- Ensure backend is running at `http://localhost:8000`
- Check `/health` endpoint: `curl http://localhost:8000/health`
- For iOS simulator, use your local IP instead of localhost

## Next Steps

1. **Customize the UI**: Edit files in `flutter_app/lib/widgets/`
2. **Add features**: Extend the API in `backend/app.py`
3. **Deploy**: 
   - Backend: Deploy to Google Cloud Run or App Engine
   - Flutter: Build for iOS/Android with `flutter build`
4. **Add authentication**: Integrate Firebase Auth

## Support

For issues or questions:
- Check the main [README.md](README.md)
- Review [ARCHITECTURE.md](ARCHITECTURE.md)
- Read [API.md](backend/API.md)
