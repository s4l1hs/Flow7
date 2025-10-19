# Deployment Guide for Flow7

This guide covers deploying Flow7 to production environments.

## Backend Deployment Options

### Option 1: Google Cloud Run (Recommended)

Google Cloud Run is ideal for the Flask backend as it auto-scales and integrates seamlessly with Firestore.

#### Prerequisites
- Google Cloud account
- `gcloud` CLI installed
- Docker installed

#### Steps

1. **Create a Dockerfile** (add to `backend/Dockerfile`):
```dockerfile
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PORT=8080
EXPOSE 8080

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app
```

2. **Update requirements.txt** (add gunicorn):
```bash
echo "gunicorn==21.2.0" >> backend/requirements.txt
```

3. **Build and deploy**:
```bash
cd backend

# Set your project ID
gcloud config set project YOUR_PROJECT_ID

# Build container
gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/flow7-backend

# Deploy to Cloud Run
gcloud run deploy flow7-backend \
  --image gcr.io/YOUR_PROJECT_ID/flow7-backend \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated
```

4. **Note the deployed URL** (e.g., `https://flow7-backend-xxx.run.app`)

### Option 2: Heroku

1. **Create Procfile** (add to `backend/Procfile`):
```
web: gunicorn app:app
```

2. **Deploy**:
```bash
cd backend
heroku create flow7-backend
git push heroku main
```

### Option 3: AWS Elastic Beanstalk

1. **Install EB CLI**:
```bash
pip install awsebcli
```

2. **Initialize and deploy**:
```bash
cd backend
eb init -p python-3.9 flow7-backend
eb create flow7-backend-env
eb deploy
```

## Frontend Deployment

### Option 1: Build Native Apps

#### Android
```bash
cd flutter_app

# Build APK
flutter build apk --release

# Build App Bundle (for Google Play)
flutter build appbundle --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

Upload to Google Play Console.

#### iOS
```bash
cd flutter_app

# Build IPA
flutter build ios --release
```

Then use Xcode to archive and upload to App Store Connect.

### Option 2: Web Deployment

#### Build Web App
```bash
cd flutter_app
flutter build web --release
```

Output directory: `build/web/`

#### Deploy to Firebase Hosting

1. **Install Firebase CLI**:
```bash
npm install -g firebase-tools
```

2. **Initialize Firebase**:
```bash
cd flutter_app
firebase init hosting
```

3. **Configure firebase.json**:
```json
{
  "hosting": {
    "public": "build/web",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ]
  }
}
```

4. **Deploy**:
```bash
firebase deploy --only hosting
```

#### Deploy to Netlify

1. **Build app**:
```bash
flutter build web --release
```

2. **Deploy via Netlify CLI**:
```bash
npm install -g netlify-cli
netlify deploy --prod --dir=build/web
```

Or drag `build/web` folder to Netlify's web interface.

## Environment Configuration

### Backend Environment Variables

For production, set these environment variables:

```bash
# Flask settings
FLASK_ENV=production
PORT=8080

# Firestore (using default credentials in Cloud Run)
# No need for GOOGLE_APPLICATION_CREDENTIALS in Cloud Run

# CORS settings (update in app.py)
ALLOWED_ORIGINS=https://your-flutter-app.com
```

### Flutter Configuration

Update API base URL in production:

**Option 1: Environment-based**

Create `flutter_app/lib/config/config.dart`:
```dart
class Config {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://flow7-backend-xxx.run.app',
  );
}
```

Then in `main.dart`:
```dart
import 'config/config.dart';

// ...
PlannerScreen(
  apiBaseUrl: Config.apiBaseUrl,
)
```

Build with:
```bash
flutter build apk --dart-define=API_BASE_URL=https://your-backend-url.com
```

**Option 2: Build-time configuration**

Create different flavors for dev/prod in Flutter.

## Security Considerations

### Backend Security

1. **API Authentication**: Add authentication middleware
```python
from functools import wraps
from flask import request, jsonify

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token or not verify_token(token):
            return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated
```

2. **Rate Limiting**:
```bash
pip install flask-limiter
```

```python
from flask_limiter import Limiter

limiter = Limiter(
    app,
    key_func=lambda: request.headers.get('X-User-Id', 'anonymous')
)

@app.route('/events', methods=['POST'])
@limiter.limit("10 per minute")
def create_event():
    # ...
```

3. **CORS Configuration**: Update for production domains
```python
from flask_cors import CORS

CORS(app, origins=['https://your-app.com'])
```

4. **Firestore Security Rules**:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /events/{eventId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null 
                   && validateEventDate(request.resource.data);
    }
    
    function validateEventDate(data) {
      let userTier = request.auth.token.tier;
      let maxDays = userTier == 'ULTRA' ? 60 : (userTier == 'PRO' ? 30 : 14);
      let maxDate = request.time + duration.value(maxDays, 'd');
      return data.date <= maxDate;
    }
  }
}
```

### Frontend Security

1. **HTTPS Only**: Ensure all API calls use HTTPS in production
2. **API Key Protection**: Don't hardcode sensitive keys
3. **Input Validation**: Validate all user inputs before API calls
4. **Secure Storage**: Use Flutter Secure Storage for sensitive data

## Monitoring and Logging

### Backend Monitoring

1. **Google Cloud Logging** (for Cloud Run):
```python
import logging
from google.cloud import logging as cloud_logging

client = cloud_logging.Client()
client.setup_logging()
```

2. **Error Tracking** (Sentry):
```bash
pip install sentry-sdk[flask]
```

```python
import sentry_sdk
from sentry_sdk.integrations.flask import FlaskIntegration

sentry_sdk.init(
    dsn="your-sentry-dsn",
    integrations=[FlaskIntegration()],
)
```

### Frontend Monitoring

1. **Firebase Crashlytics** (for mobile apps)
2. **Google Analytics** (for web)
3. **Sentry** (for error tracking)

## Scaling Considerations

### Backend Scaling

1. **Cloud Run**: Auto-scales based on traffic
2. **Firestore**: Automatically scales (watch quota limits)
3. **Caching**: Add Redis for frequently accessed data
4. **CDN**: Use Cloud CDN for static assets

### Database Optimization

1. **Firestore Indexes**: Create composite indexes for complex queries
2. **Pagination**: Implement cursor-based pagination for large result sets
3. **Query Optimization**: Limit fields returned in queries

## Cost Optimization

### Free Tier Limits

- **Firestore**: 1GB storage, 50K reads/day, 20K writes/day
- **Cloud Run**: 2 million requests/month, 360K GB-seconds compute
- **Firebase Hosting**: 10GB storage, 360MB/day transfer

### Tips to Stay in Free Tier

1. Enable caching to reduce Firestore reads
2. Optimize queries to fetch only needed data
3. Use Cloud Run's minimum instances = 0 for dev
4. Compress responses with gzip

## Backup and Recovery

### Firestore Backup

1. **Automatic Backups** (Firebase Blaze plan):
```bash
gcloud firestore export gs://your-bucket/backups
```

2. **Scheduled Backups** (Cloud Scheduler):
Set up automatic daily backups.

### Disaster Recovery Plan

1. Keep configuration in version control
2. Document deployment procedures
3. Test recovery procedures regularly
4. Monitor service health

## CI/CD Pipeline

### GitHub Actions Example

Create `.github/workflows/deploy.yml`:
```yaml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Cloud SDK
        uses: google-github-actions/setup-gcloud@v0
        with:
          service_account_key: ${{ secrets.GCP_SA_KEY }}
          project_id: ${{ secrets.GCP_PROJECT_ID }}
      
      - name: Deploy to Cloud Run
        run: |
          cd backend
          gcloud builds submit --tag gcr.io/${{ secrets.GCP_PROJECT_ID }}/flow7-backend
          gcloud run deploy flow7-backend \
            --image gcr.io/${{ secrets.GCP_PROJECT_ID }}/flow7-backend \
            --platform managed \
            --region us-central1

  deploy-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        
      - name: Build Web
        run: |
          cd flutter_app
          flutter build web --release
          
      - name: Deploy to Firebase
        uses: w9jds/firebase-action@master
        with:
          args: deploy --only hosting
        env:
          FIREBASE_TOKEN: ${{ secrets.FIREBASE_TOKEN }}
```

## Post-Deployment Checklist

- [ ] Update API base URL in Flutter app
- [ ] Configure CORS for production domain
- [ ] Set up Firestore security rules
- [ ] Enable HTTPS/SSL
- [ ] Configure monitoring and alerts
- [ ] Set up automated backups
- [ ] Test all tier limits in production
- [ ] Load test API endpoints
- [ ] Review and optimize costs
- [ ] Document production URLs
- [ ] Set up status page
