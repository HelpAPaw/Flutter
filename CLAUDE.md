# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Help A Paw is a mobile application for reporting emergency signals about animals in need. Users can create signals on a map, and nearby volunteers receive push notifications. The app supports anonymous usage with optional authenticated features.

## Common Commands

### Flutter Development
```bash
# Run the app (uses FVM)
flutter run

# Run on specific device
flutter run -d <device_id>

# Build Android APK
flutter build apk

# Build iOS (requires macOS)
flutter build ios

# Run linting
flutter analyze lib

# Run auto-fix
dart fix lib --apply

# Run widget tests
flutter test

# Run integration tests (requires device/emulator)
flutter test integration_test/
```

### Firebase Functions
```bash
cd functions

# Build TypeScript
npm run build

# Deploy functions to Firebase
npm run deploy

# Run local emulator
npm run serve

# View function logs
npm run logs
```

### Firebase Emulators
```bash
# Start all Firebase emulators
firebase emulators:start

# Emulator ports (see firebase.json):
# - Auth: 9099
# - Functions: 5001
# - Firestore: 8080
# - Storage: 9199
```

## Architecture

### Project Structure
```
lib/
├── main.dart                    # App entry point with GoRouter configuration
├── l10n/                        # Localization (en, bg)
└── src/
    ├── config/                  # Firebase options
    ├── models/                  # Data models (Signal, VetClinic)
    ├── services/                # Business logic & external integrations
    ├── viewmodels/              # Currently minimal (only map_view_model.dart)
    └── widgets/                 # UI screens and components
```

### Key Architectural Patterns

**State Management**: Primarily StatefulWidget with setState(). No state management library (Redux, Riverpod, etc.) is used. State lives in individual screen widgets, particularly `MapScreen` which holds most app state.

**Navigation**: GoRouter with declarative routing. All routes defined in `main.dart`. Router is passed to `NotificationService` for deep linking from push notifications.

**Firebase Integration**:
- **Authentication**: FirebaseAuth with anonymous sign-in by default, optional email/password or Google OAuth
- **Database**: Cloud Firestore for signals and user data
- **Storage**: Firebase Storage for signal photos
- **Messaging**: FCM for push notifications about nearby signals
- **Functions**: TypeScript Cloud Functions for background tasks (notification distribution)
- **App Check**: Enabled in debug mode (both platforms)

**Geolocation**: Uses `geoflutterfire_plus` for geoqueries. Signals are stored with GeoPoints and queried by radius from user location. Map initially centers on user's location if permissions are granted; otherwise falls back to Sofia, Bulgaria (42.6977, 23.3219).

**Notification Flow**:
1. Two-phase initialization: basic setup on app start, full setup after permission grant
2. NotificationService uses both FCM (remote) and flutter_local_notifications (local display)
3. Background message handler must be top-level function
4. Notification tap navigates via GoRouter to signal details

**Email Verification**: Users who sign up with email/password are redirected to `/verify_email` until they verify. Google OAuth users skip this.

### Important Files

- `lib/src/widgets/map_page.dart` - Main screen with Google Maps, signal markers, filters, vet clinics
- `lib/src/services/notification_service.dart` - FCM integration with two-phase init pattern
- `lib/src/services/location_service.dart` - Geolocation and permission handling
- `lib/main.dart` - App initialization, Firebase setup, routing configuration
- `functions/src/index.ts` - Cloud Functions for notification distribution

### Data Models

**Signal**: Animal emergency report with title, description, location (GeoPoint), type (0-6), status (0-2), photos, reporter reference, contact phone, creation timestamp.

**VetClinic**: Veterinary clinic with name, location, contact info. Fetched from Google Places API via Cloud Functions.

### Integration Tests

Integration tests use `integration_test` framework. Note: There was a recent issue with coordinate-based tapping on map markers, which was solved by using Flutter's integration_test instead of UI Automator.

## Firebase Configuration

### Environment Files
- iOS debug: `ios/Runner/GoogleService-Info-Debug.plist`
- iOS release: `ios/Runner/GoogleService-Info-Release.plist`
- Android: `android/app/google-services.json`

Scripts in `ios/scripts/` select the correct plist based on build configuration.

### Build Configuration
- **Android**: Compile SDK 35, Min SDK 23, Target SDK 35, Java 17, Gradle JVM heap 4GB
  - Debug builds use package name: `org.helpapaw.helpapaw.debug`
  - Release builds use: `org.helpapaw.helpapaw`
- **iOS**: Deployment target in Xcode project
  - Debug builds use bundle identifier: `com.helpapaw.helpapaw.debug`
  - Release builds use: `com.helpapaw.helpapaw`
- **Localization**: ARB files in `lib/l10n/` (en, bg), configured via `l10n.yaml`

## Development Workflow

When fixing memory leaks, check for setState calls on unmounted widgets. Recent fix: `8a18695` addressed setState after dispose in map screen.

When adding new routes, update the GoRouter configuration in `main.dart` and ensure redirect logic accounts for auth state.

When modifying notification behavior, remember the two-phase initialization pattern - permission requests must not happen during app startup to avoid iOS rejection.

The map's initial location logic: `_getUserLocation()` is called during `initState()` and will update the map center and signal stream to the user's actual location if permissions are available. Sofia coordinates are only used as the initial fallback before location is determined.
