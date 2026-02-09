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

## Automated Testing

### MCP Mobile Tools Integration

This project uses **two complementary MCP servers** for cross-device automated testing on both iOS (physical devices) and Android devices:

1. **mobile-mcp** - Lightweight, accessibility-tree based automation with screenshot fallback
2. **appium-mcp** - Advanced automation with AI-powered locator generation and W3C Actions API

**IMPORTANT: Prefer using appium-mcp over mobile-mcp whenever possible.** Appium-mcp provides more reliable element-based interactions, better cross-platform support, and advanced features like AI-powered locator generation.

The testing infrastructure is documented in detail in:
- `TEST_RESULTS_CROSS_DEVICE_COMPREHENSIVE.md` - Cross-device test results and methodologies
- `APPIUM_MCP_GUIDE.md` - Complete guide for appium-mcp installation, configuration, and usage

#### Device Setup

**iOS (Physical Devices):**

**WebDriverAgent Location:** `/Users/milen/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/`

**iPad UDID:** `6c602c36e83e447ac48c4477f18fac43d1e00175`

1. Install go-ios: `npm install -g go-ios`
2. WebDriverAgent is already installed via Appium (see location above)
3. Configure code signing in Xcode (one-time setup)
4. Build and deploy to device:
   ```bash
   cd /Users/milen/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent
   xcodebuild -project WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner -destination 'platform=iOS,id=6c602c36e83e447ac48c4477f18fac43d1e00175' test
   ```
5. Start tunneling: `ios tunnel start --userspace`
6. Port forward: `ios forward 8100 8100 --udid 6c602c36e83e447ac48c4477f18fac43d1e00175`
7. Verify: MCP tools should detect device via `mobile_list_available_devices`

**Android:**
MCP tools connect directly to Android devices via ADB - no special setup required beyond normal ADB connectivity.

### Precise Element Targeting Methodology

**Critical Discovery (Jan 22, 2026):** Many element interaction failures are NOT framework bugs but rather **imprecise coordinate targeting**. This was proven when Google Maps info window taps appeared to fail systematically, but actually worked perfectly when tapped at exact pixel coordinates.

#### When Standard Methods Fail

If `mobile_list_elements_on_screen` doesn't provide the element you need, or if coordinate tapping consistently fails, use **pixel-level screenshot analysis**:

#### Pixel-Level Targeting Method

**Prerequisites:**
```bash
pip3 install Pillow
```

**Process:**

1. **Capture Screenshot**
```python
mobile_take_screenshot(device=DEVICE_ID)
```

2. **Analyze Pixels with Python PIL**

Save this script as `find_element_pixels.py`:
```python
from PIL import Image
import sys

def find_element_by_color(image_path, target_rgb, threshold=10):
    """
    Find element boundaries by scanning for specific background color.

    Args:
        image_path: Path to screenshot
        target_rgb: Target color as (R, G, B) tuple
        threshold: Color matching threshold (0-255)
    """
    img = Image.open(image_path)
    width, height = img.size

    matching_pixels = []

    # Scan entire image
    for y in range(0, height, 2):  # Sample every 2 pixels for speed
        for x in range(0, width, 2):
            pixel = img.getpixel((x, y))
            r, g, b = pixel[:3]

            # Check if pixel matches target color within threshold
            if (abs(r - target_rgb[0]) <= threshold and
                abs(g - target_rgb[1]) <= threshold and
                abs(b - target_rgb[2]) <= threshold):
                matching_pixels.append((x, y))

    if matching_pixels:
        xs = [p[0] for p in matching_pixels]
        ys = [p[1] for p in matching_pixels]

        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)
        center_x = (min_x + max_x) // 2
        center_y = (min_y + max_y) // 2

        print(f"Element found!")
        print(f"  X range: {min_x} to {max_x} (width: {max_x - min_x}px)")
        print(f"  Y range: {min_y} to {max_y} (height: {max_y - min_y}px)")
        print(f"  CENTER: ({center_x}, {center_y})")

        return (center_x, center_y)
    else:
        print(f"No pixels found matching RGB{target_rgb}")
        return None

if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: python find_element_pixels.py <image_path> <R> <G> <B>")
        sys.exit(1)

    image_path = sys.argv[1]
    target_rgb = (int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]))

    find_element_by_color(image_path, target_rgb)
```

3. **Usage Example - Google Maps Info Window**

Info windows have a cream-colored background (RGB 255, 243, 219):

```bash
# Take screenshot with info window visible
mobile_take_screenshot(device) → saved as screenshot.png

# Find info window coordinates
python3 find_element_pixels.py screenshot.png 255 243 219

# Output:
# Element found!
#   X range: 352 to 849 (width: 497px)
#   Y range: 800 to 949 (height: 149px)
#   CENTER: (600, 874)

# Tap at exact center
mobile_click_on_screen_at_coordinates(device, x=600, y=874)
```

**Result:** Info window tap works perfectly, navigates to signal details.

#### Alternative: Scan for Element Edges

For elements without distinct background colors, scan for edge contrasts:

```python
def find_element_by_edges(image_path):
    """Find rectangular elements by detecting edge contrasts"""
    img = Image.open(image_path).convert('L')  # Convert to grayscale
    pixels = img.load()
    width, height = img.size

    edges = []
    for y in range(1, height - 1):
        for x in range(1, width - 1):
            # Calculate gradient
            gx = abs(int(pixels[x+1, y]) - int(pixels[x-1, y]))
            gy = abs(int(pixels[x, y+1]) - int(pixels[x, y-1]))
            gradient = gx + gy

            if gradient > 100:  # Threshold for edge detection
                edges.append((x, y))

    # Find rectangular regions from edges
    # (implementation depends on element shape)
    return edges
```

#### When to Use This Method

✅ **USE pixel analysis when:**
- `mobile_list_elements_on_screen` doesn't show the element
- Element is part of a custom UI (like Google Maps info windows)
- Coordinate tapping fails consistently despite trying multiple approaches
- Element has a visually distinct appearance (color, shape, contrast)

❌ **DON'T use pixel analysis when:**
- Element is in accessibility tree - use `mobile_list_elements_on_screen` instead
- Element coordinates are already known and working
- You're on first attempt - try standard methods first

#### Success Cases

1. **Google Maps Info Windows** (Jan 22, 2026)
   - Problem: Tapping closed window instead of navigating
   - Solution: Pixel analysis found exact center (600, 874)
   - Result: Perfect navigation to signal details

2. **Complex Custom UI Elements**
   - When Flutter widgets don't expose accessibility nodes
   - When standard tapping coordinates are slightly off target
   - When precision matters (small tappable areas)

#### Key Lessons

- "Framework limitation" is often "imprecise coordinates"
- Always verify with pixel-level analysis before concluding something is impossible
- Screenshot + Python PIL is faster than repeatedly trying different coordinates
- Document successful color values for reusable targeting (e.g., info window cream: RGB 255,243,219)

### Testing Best Practices

1. **Always use `mobile_list_elements_on_screen` first** - it's faster and more reliable when available
2. **Save screenshots for debugging** - easier to diagnose issues visually
3. **Document color values** - reuse known element colors in future tests
4. **Verify element presence** before tapping - take screenshot, analyze, then tap
5. **Use exact coordinates** from pixel analysis - don't approximate

### Test Documentation

All cross-device test results are documented in:
- `TEST_RESULTS_CROSS_DEVICE_COMPREHENSIVE.md` - Full test report with all findings
- Test execution dates, device IDs, and exact procedures are recorded for reproducibility
