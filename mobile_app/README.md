# Soil Mobile App

Flutter mobile frontend for:

GIS-Enabled and Mobile Decision-Support Application for Deep Learning-Based Soil Classification and Recommendation

## What is included

- `lib/` app source wired to the existing FastAPI backend
- API integration for login, registration, dashboard, climate, leases, productivity, and AI image analysis
- Simple MVP screens for the five architecture modules

## Backend URL

The app uses a compile-time backend URL from:

`lib/config/api_config.dart`

Default:

`http://10.0.2.2:8000`

Use `10.0.2.2` for the Android emulator. For a real phone, replace it with your computer's LAN IP.

## Suggested run flow

1. Install Flutter on your machine.
2. Open this `mobile_app` folder in your Flutter environment.
3. If your machine needs native platform folders, generate them with Flutter tooling before running.
4. Run:

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

For a real device, replace `10.0.2.2` with the backend machine IP, for example:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

## Android permissions needed

Add these permissions to `android/app/src/main/AndroidManifest.xml` if your generated Flutter project does not already include them:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
```
