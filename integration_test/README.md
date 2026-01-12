# Integration Tests

This directory contains Flutter integration tests that solve the coordinate-based tapping issues encountered with ADB/UI Automator testing.

## Why Integration Tests?

Flutter apps don't map directly to native view hierarchies, causing coordinate mismatches with native automation tools. Integration tests work at the Flutter widget layer, providing:

- **Accurate widget interaction** - No coordinate translation issues
- **Better test reliability** - Tests work across different screen sizes
- **Semantic-based finding** - Use widget properties instead of coordinates
- **Support for complex widgets** - Dropdowns, overlays, and custom widgets work correctly

## Test Files

### 1. `signal_submission_test.dart`
Tests signal submission functionality that was blocked by submit button coordinate issues.

**Tests:**
- Submit new signal successfully
- Submit button responds to tap
- Signal type dropdown interaction

### 2. `map_interaction_test.dart`
Tests map marker interactions and navigation that were problematic with coordinate-based tapping.

**Tests:**
- Map and marker interaction
- Navigate to signal details (via My Signals alternative)
- Filter signals on map
- Search vet clinics

### 3. `notification_test.dart`
Tests notification and deep linking scenarios.

**Tests:**
- Deep link navigation to signal details
- Comment notification flow
- Status change notification flow
- Notification settings page interaction

## Running Tests

**Prerequisites:**
- **Sign in manually** on the device before running tests (tests will skip if anonymous)
  - Open the app → Menu → Sign In → Use email/password or Google
- Grant necessary permissions (location, camera, notifications) beforehand

**Note:** Automated sign-in is complex due to Firebase Auth state timing. Manual sign-in before test runs is recommended.

### Run a specific test on a device:
```bash
flutter test integration_test/signal_submission_test.dart -d DEVICE_ID
```

### Run all integration tests:
```bash
flutter test integration_test/ -d DEVICE_ID
```

### Run on specific devices:
```bash
# Phone
flutter test integration_test/ -d 74ef078e

# Tablet
flutter test integration_test/ -d R9PW402KZEE
```

### With verbose output:
```bash
flutter test integration_test/signal_submission_test.dart -d 74ef078e --verbose
```

## Test Results vs ADB Testing

| Scenario | ADB/UI Automator | Integration Test |
|----------|------------------|------------------|
| Submit signal button | ❌ Coordinate mismatch | ✅ Works with find.byIcon() |
| Map marker info window | ❌ Tap doesn't navigate | ✅ Alternative via My Signals |
| Dropdown interaction | ❌ Complex coordinate calc | ✅ find.byType(DropdownButton) |
| Overlay elements | ❌ Z-order issues | ✅ Flutter layer handles it |

## Key Improvements

1. **No coordinate calculations** - Use semantic finders instead
2. **Screen size independent** - Tests work on any device
3. **Flutter-aware** - Understands widget hierarchy correctly
4. **Better maintainability** - Tests read like user interactions

## Best Practices

1. **Use semantic finders first:**
   ```dart
   find.byTooltip('Add new signal')
   find.byIcon(Icons.send)
   find.text('Submit')
   ```

2. **Use type finders for widgets:**
   ```dart
   find.byType(DropdownButton<int>)
   find.byType(TextField)
   ```

3. **Pump and settle after interactions:**
   ```dart
   await tester.tap(button);
   await tester.pumpAndSettle();
   ```

4. **Wait for async operations:**
   ```dart
   await tester.pumpAndSettle(const Duration(seconds: 2));
   ```

5. **Use coordinates only for native views:**
   - Google Maps markers (not Flutter widgets)
   - Calculate based on widget bounds, not hardcoded

## Debugging Tests

### Run with driver logs:
```bash
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/signal_submission_test.dart \
  -d DEVICE_ID
```

### Check for widget presence:
```dart
expect(find.byIcon(Icons.send), findsOneWidget);
```

### Print debug info:
```dart
print('Found ${googleMap.markers.length} markers');
```

## Known Limitations

1. **Google Maps markers** - Still require coordinate-based tapping since they're native views, but integration_test handles this better than ADB
2. **Camera/Gallery pickers** - May need special handling for native dialogs
3. **System permissions** - Should be granted before running tests

## References

- [Flutter Integration Testing Guide](https://docs.flutter.dev/cookbook/testing/integration/introduction)
- [Integration Test Migration](https://docs.flutter.dev/testing/integration-tests/migration)
- [WidgetTester API](https://api.flutter.dev/flutter/flutter_test/WidgetTester-class.html)
