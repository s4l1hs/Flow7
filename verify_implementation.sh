#!/bin/bash

# Verification script for Flutter Calendar View implementation

echo "========================================="
echo "Flow7 Calendar View Implementation Check"
echo "========================================="
echo ""

# Check if all required files exist
echo "Checking for required files..."
files=(
  "pubspec.yaml"
  "lib/main.dart"
  "lib/screens/main_screen.dart"
  "lib/widgets/day_card.dart"
  "lib/utils/date_utils.dart"
  "test/date_utils_test.dart"
  "test/day_card_test.dart"
)

all_found=true
for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    echo "✓ $file"
  else
    echo "✗ $file (MISSING)"
    all_found=false
  fi
done

echo ""

# Check for key implementation components
echo "Checking implementation components..."

# Check for generateWeekDays function
if grep -q "generateWeekDays" lib/utils/date_utils.dart; then
  echo "✓ generateWeekDays function found"
else
  echo "✗ generateWeekDays function not found"
  all_found=false
fi

# Check for getWeekStart function
if grep -q "getWeekStart" lib/utils/date_utils.dart; then
  echo "✓ getWeekStart function found"
else
  echo "✗ getWeekStart function not found"
  all_found=false
fi

# Check for DayCard widget
if grep -q "class DayCard" lib/widgets/day_card.dart; then
  echo "✓ DayCard widget found"
else
  echo "✗ DayCard widget not found"
  all_found=false
fi

# Check for MainScreen widget
if grep -q "class MainScreen" lib/screens/main_screen.dart; then
  echo "✓ MainScreen widget found"
else
  echo "✗ MainScreen widget not found"
  all_found=false
fi

# Check for PageView in MainScreen
if grep -q "PageView" lib/screens/main_screen.dart; then
  echo "✓ PageView (horizontal scrolling) found in MainScreen"
else
  echo "✗ PageView not found in MainScreen"
  all_found=false
fi

echo ""

# Summary
if [ "$all_found" = true ]; then
  echo "========================================="
  echo "✓ All components verified successfully!"
  echo "========================================="
  exit 0
else
  echo "========================================="
  echo "✗ Some components are missing!"
  echo "========================================="
  exit 1
fi
