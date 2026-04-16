# Android Play Release Notes

This repo is now wired for a real Android upload key instead of silently using the debug key for release.

## Production package

The Android app is configured for:

- `com.theconquerorscourt.vault`

That package already exists in the Firebase config at:

- `android/app/google-services.json`

## Release signing

1. Copy `android/key.properties.template` to `android/key.properties`.
2. Generate or choose your upload keystore.
3. Fill in:
   - `storeFile`
   - `storePassword`
   - `keyAlias`
   - `keyPassword`

Example key generation command:

```powershell
keytool -genkeypair -v -keystore android\upload-keystore.jks -alias upload -keyalg RSA -keysize 4096 -validity 9125
```

After that, release builds work normally:

```powershell
flutter build appbundle --release
```

If you need a one-off local validation build before the real keystore is ready, you can still opt into debug signing explicitly:

```powershell
Set-Location android
.\gradlew.bat :app:bundleRelease -PVAULT_ALLOW_DEBUG_RELEASE_SIGNING=true
```

Do not upload a debug-signed bundle to production.

## Privacy policy

Public-facing privacy policy files live at:

- `docs/privacy-policy.md`
- `web/privacy-policy.html`
- `docs/terms-of-service.md`
- `web/terms-of-service.html`

If you are hosting the privacy page from the Flutter web build output, use:

```powershell
.\tool\build_web_release.ps1
```

That script builds the web app and copies the public legal pages into `build/web/`.

## Play Console copy

Google Play listing copy and Data safety drafting now live at:

- `docs/android-play-store-listing.md`
- `docs/android-play-data-safety.md`

## Current release output

The standard release bundle path is:

- `build/app/outputs/bundle/release/app-release.aab`
