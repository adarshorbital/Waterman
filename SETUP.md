# WaterMan App — Setup Instructions

This is source code only, not a compiled/scaffolded Flutter project (no Flutter SDK or
Xcode toolchain is available in the environment that generated it). Follow these steps
to get a real, buildable project.

## 1. Scaffold the project

```
flutter create waterman_app
cd waterman_app
```

Delete the generated `lib/main.dart` and the generated `pubspec.yaml`'s dependency
section, then copy in the files from this bundle:

- `pubspec.yaml` → replace generated one (or merge the `dependencies:` block)
- `lib/main.dart`
- `lib/ble_service.dart`
- `lib/models/pump_status.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/manual_tab.dart`
- `lib/screens/timed_tab.dart`
- `lib/screens/schedule_tab.dart`

Then:

```
flutter pub get
```

## 2. Android permissions

Edit `android/app/src/main/AndroidManifest.xml`, inside `<manifest>` (above
`<application>`):

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
```

Also confirm `minSdkVersion` in `android/app/build.gradle` is at least 21 (23+
recommended for reliable BLE scan behavior).

flutter_blue_plus requests these at runtime via `permission_handler` — no extra Dart
code needed beyond what's included, but the manifest entries are required or the app
will crash on first scan.

## 3. iOS permissions

Edit `ios/Runner/Info.plist`, add inside the outer `<dict>`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>WaterMan needs Bluetooth to control your plant watering pump.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>WaterMan needs Bluetooth to control your plant watering pump.</string>
```

iOS builds require Xcode on macOS. For your own device without a paid Apple Developer
account, use a free personal-team signing certificate (Xcode → Signing & Capabilities) —
the app will run for 7 days before needing a rebuild/re-sign, which is fine for personal
use but worth knowing going in. A $99/year Apple Developer account removes that limit.

## 4. Build & run

```
flutter run          # deploys to a connected/simulated device
flutter build apk     # Android release APK
flutter build ios     # iOS build (macOS + Xcode required)
```

## 5. Firmware

Flash `WaterMan_V3.ino` to the ESP32-S3 (replaces the previous sketch — same board,
same BLE service UUID, adds two new characteristics' worth of protocol on top of the
existing control characteristic). Requires the `Preferences.h` library (bundled with
the ESP32 Arduino core) and `BLE2902.h` (bundled with the ESP32 BLE library you're
already using).

## Known limitation (by design, per your choice)

Time sync is phone-supplied on each connect — there's no onboard RTC or WiFi/NTP. If
the board loses power and no phone connects before the next scheduled watering time,
that day's watering will be skipped (it will not fire on stale/unsynced time). The app
surfaces this via a "time not synced" warning on the Schedule tab and a banner at the
top of the app. If this becomes a problem in practice, a DS3231 RTC module (~$2, I2C)
is a low-effort upgrade path later.
