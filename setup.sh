#!/bin/bash

# Flow7 Setup Script
# This script helps set up the Flow7 project for development

echo "========================================="
echo "Flow7 - Weekly Planner Setup"
echo "========================================="
echo ""

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed. Please install Python 3.8 or higher."
    exit 1
fi

echo "✓ Python 3 found: $(python3 --version)"

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "Warning: Flutter is not installed."
    echo "Please install Flutter from https://flutter.dev/docs/get-started/install"
    FLUTTER_INSTALLED=false
else
    echo "✓ Flutter found: $(flutter --version | head -n 1)"
    FLUTTER_INSTALLED=true
fi

echo ""
echo "========================================="
echo "Setting up Backend"
echo "========================================="

cd backend

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install dependencies
echo "Installing Python dependencies..."
pip install -r requirements.txt

# Create .env file if it doesn't exist
if [ ! -f ".env" ]; then
    echo "Creating .env file from template..."
    cp .env.example .env
fi

echo ""
echo "Backend setup complete!"
echo ""
echo "⚠️  IMPORTANT: You need to set up Firebase/Firestore:"
echo "   1. Go to https://console.firebase.google.com/"
echo "   2. Create a new project or select an existing one"
echo "   3. Enable Firestore Database"
echo "   4. Download the service account key JSON"
echo "   5. Save it as 'backend/serviceAccountKey.json'"
echo ""

cd ..

if [ "$FLUTTER_INSTALLED" = true ]; then
    echo "========================================="
    echo "Setting up Flutter App"
    echo "========================================="
    
    cd flutter_app
    
    echo "Getting Flutter dependencies..."
    flutter pub get
    
    echo ""
    echo "Flutter app setup complete!"
    echo ""
    
    cd ..
fi

echo "========================================="
echo "Setup Summary"
echo "========================================="
echo ""
echo "Backend: ✓ Ready"
if [ "$FLUTTER_INSTALLED" = true ]; then
    echo "Flutter: ✓ Ready"
else
    echo "Flutter: ✗ Not installed"
fi
echo ""
echo "Next steps:"
echo "1. Set up Firebase/Firestore (see instructions above)"
echo "2. Start the backend: cd backend && source venv/bin/activate && python app.py"
if [ "$FLUTTER_INSTALLED" = true ]; then
    echo "3. Run the Flutter app: cd flutter_app && flutter run"
else
    echo "3. Install Flutter and run: cd flutter_app && flutter pub get && flutter run"
fi
echo ""
echo "For more information, see README.md"
echo ""
