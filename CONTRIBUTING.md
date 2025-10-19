# Contributing to Flow7

Thank you for your interest in contributing to Flow7! This guide will help you get started.

## 🌟 Ways to Contribute

- 🐛 **Bug Reports**: Found a bug? Open an issue!
- ✨ **Feature Requests**: Have an idea? We'd love to hear it!
- 📝 **Documentation**: Improve docs, add examples
- 🔧 **Code**: Fix bugs, add features, improve performance
- 🎨 **Design**: UI/UX improvements, icons, themes
- 🧪 **Testing**: Add tests, improve coverage

## 🚀 Getting Started

### 1. Fork and Clone

```bash
# Fork the repository on GitHub
# Then clone your fork
git clone https://github.com/YOUR_USERNAME/Flow7.git
cd Flow7
```

### 2. Set Up Development Environment

```bash
# Run the setup script
./setup.sh

# Or manually:
cd backend
pip install -r requirements.txt
cd ../flutter_app
flutter pub get
```

### 3. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/bug-description
```

## 📋 Development Guidelines

### Code Style

#### Flutter/Dart
- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart)
- Use `flutter format` before committing
- Run `flutter analyze` to check for issues
- Add comments for complex logic

```dart
// Good
class Event {
  final String title;
  final DateTime date;
  
  Event({required this.title, required this.date});
}

// Bad
class event {
  String t;
  var d;
}
```

#### Python
- Follow [PEP 8](https://pep8.org/)
- Use type hints
- Maximum line length: 88 characters (Black formatter)
- Use docstrings for functions/classes

```python
# Good
def validate_date_range(date: datetime, user_tier: UserTier) -> bool:
    """
    Validates if a date is within the allowed range for a user tier.
    
    Args:
        date: The date to validate
        user_tier: The user's subscription tier
        
    Returns:
        True if date is within allowed range, False otherwise
    """
    pass

# Bad
def validate(d, t):
    pass
```

### Git Commit Messages

Use clear, descriptive commit messages:

```bash
# Good
git commit -m "Add recurring event support to Event model"
git commit -m "Fix date validation for leap years"
git commit -m "Update API documentation for /events endpoint"

# Bad
git commit -m "update"
git commit -m "fix bug"
git commit -m "changes"
```

Format:
```
<type>: <short description>

<optional longer description>

<optional footer>
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Testing

#### Backend Tests

Always add tests for new features:

```python
# backend/test_your_feature.py
import unittest
from your_module import your_function

class TestYourFeature(unittest.TestCase):
    def test_basic_functionality(self):
        result = your_function()
        self.assertEqual(result, expected_value)
```

Run tests:
```bash
cd backend
python -m unittest discover
```

#### Flutter Tests

Add widget tests for UI components:

```dart
// flutter_app/test/widget_test.dart
testWidgets('Event displays title', (WidgetTester tester) async {
  final event = Event(
    title: 'Test Event',
    date: DateTime.now(),
    startTime: '09:00',
    endTime: '10:00',
  );
  
  await tester.pumpWidget(EventCard(event: event));
  
  expect(find.text('Test Event'), findsOneWidget);
});
```

Run tests:
```bash
cd flutter_app
flutter test
```

### Documentation

- Update README.md for major changes
- Add docstrings/comments for new functions
- Update API.md for API changes
- Include examples for new features

## 🔄 Pull Request Process

### 1. Before Submitting

- [ ] Code follows style guidelines
- [ ] All tests pass
- [ ] New tests added for new features
- [ ] Documentation updated
- [ ] No merge conflicts with main
- [ ] Commit messages are clear

### 2. Submit PR

1. Push your branch:
   ```bash
   git push origin feature/your-feature-name
   ```

2. Open a Pull Request on GitHub

3. Fill out the PR template:
   ```markdown
   ## Description
   Brief description of changes
   
   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Documentation update
   - [ ] Performance improvement
   
   ## Testing
   - Describe how you tested the changes
   - List any new tests added
   
   ## Checklist
   - [ ] Code follows style guidelines
   - [ ] Tests pass
   - [ ] Documentation updated
   ```

### 3. Review Process

- Maintainers will review your PR
- Address any feedback or requested changes
- Once approved, your PR will be merged!

## 🐛 Bug Reports

Use the issue template:

```markdown
**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce:
1. Go to '...'
2. Click on '...'
3. See error

**Expected behavior**
What you expected to happen.

**Screenshots**
If applicable, add screenshots.

**Environment:**
- OS: [e.g., iOS 14, Android 11]
- Flutter version: [e.g., 3.0.0]
- Python version: [e.g., 3.9]

**Additional context**
Any other relevant information.
```

## ✨ Feature Requests

Use the issue template:

```markdown
**Is your feature request related to a problem?**
A clear description of the problem.

**Describe the solution you'd like**
A clear description of what you want to happen.

**Describe alternatives you've considered**
Other solutions or features you've considered.

**Additional context**
Any other context, mockups, or screenshots.
```

## 📚 Development Tips

### Working with Firestore

For local development, you can use the Firestore Emulator:

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Start emulator
firebase emulators:start --only firestore

# Update backend to use emulator
# In firestore_service.py:
os.environ['FIRESTORE_EMULATOR_HOST'] = 'localhost:8080'
```

### Hot Reload in Flutter

Use hot reload for faster development:

```bash
# Run app
flutter run

# In terminal, press:
# r - Hot reload
# R - Hot restart
# q - Quit
```

### API Testing

Use the test script:

```bash
cd backend
./test_api.sh
```

Or use curl directly:

```bash
# Test health check
curl http://localhost:8000/health

# Test tier info
curl -H "X-User-Tier: FREE" http://localhost:8000/tier-info

# Create event
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-User-Tier: FREE" \
  -d '{"date":"2024-01-20T00:00:00","start_time":"09:00","end_time":"10:00","title":"Test"}' \
  http://localhost:8000/events
```

### Debugging

#### Flutter Debugging

Use Flutter DevTools:

```bash
flutter run
# Open DevTools URL shown in console
```

Add debug prints:

```dart
print('Debug: $variable');
debugPrint('More detailed: $object');
```

#### Python Debugging

Use Python debugger:

```python
import pdb; pdb.set_trace()
```

Or add print statements:

```python
print(f"Debug: {variable}")
```

## 🎯 Good First Issues

Looking for something to work on? Check issues labeled:
- `good first issue` - Great for newcomers
- `help wanted` - We'd love help on these
- `documentation` - Improve docs

## 💡 Feature Ideas

Some features we'd love to see:

### High Priority
- [ ] User authentication (Firebase Auth)
- [ ] Recurring events
- [ ] Event categories/colors
- [ ] Push notifications
- [ ] Offline support

### Medium Priority
- [ ] Calendar sync (Google, Apple)
- [ ] Team/shared calendars
- [ ] Event attachments
- [ ] Time zone support
- [ ] Search functionality

### Nice to Have
- [ ] Dark mode
- [ ] Multiple themes
- [ ] Analytics dashboard
- [ ] Export events (CSV, PDF)
- [ ] Voice input for events

## 📞 Getting Help

- 💬 Open a discussion on GitHub
- 📧 Email maintainers
- 📖 Check existing documentation
- 🔍 Search closed issues

## 🏆 Recognition

Contributors will be:
- Listed in CONTRIBUTORS.md
- Mentioned in release notes
- Credited in the project

## 📄 License

By contributing, you agree that your contributions will be licensed under the MIT License.

## 🙏 Thank You!

Every contribution helps make Flow7 better. We appreciate your time and effort!

---

**Questions?** Open an issue or start a discussion!
