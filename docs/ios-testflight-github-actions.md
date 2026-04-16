# iOS TestFlight via GitHub Actions

This repo now includes a macOS GitHub Actions workflow at `.github/workflows/ios_testflight.yml` and a fastlane lane at `fastlane/Fastfile` for TestFlight uploads.

## What the workflow expects

Add these GitHub repository secrets before you run the workflow:

- `IOS_RELEASE_XCCONFIG_B64`
- `IOS_GOOGLE_SERVICE_INFO_PLIST_B64`
- `IOS_CERTIFICATE_P12_B64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_B64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_B64`

Optional:

- `APP_STORE_CONNECT_TEAM_ID`

## Release xcconfig secret

Create a real release override file from `ios/Flutter/ReleaseSecrets.template.xcconfig`, then base64-encode it into `IOS_RELEASE_XCCONFIG_B64`.

Minimum values:

```xcconfig
APP_DISPLAY_NAME = The Vault
APP_BUNDLE_IDENTIFIER = com.yourteam.thevault
APP_TESTS_BUNDLE_IDENTIFIER = $(APP_BUNDLE_IDENTIFIER).RunnerTests
APPLE_DEVELOPMENT_TEAM = ABCDE12345
```

PowerShell example:

```powershell
[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes("C:\Users\Varnok\The-Vault\ios\Flutter\ReleaseSecrets.xcconfig")
)
```

## Firebase plist secret

Download `GoogleService-Info.plist` for the iOS app in Firebase, then base64-encode it into `IOS_GOOGLE_SERVICE_INFO_PLIST_B64`.

PowerShell example:

```powershell
[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes("C:\path\to\GoogleService-Info.plist")
)
```

## Signing secrets

You need:

- an iOS distribution certificate exported as `.p12`
- the matching password
- an App Store provisioning profile for the same bundle identifier

Base64-encode the `.p12` and `.mobileprovision` files into:

- `IOS_CERTIFICATE_P12_B64`
- `IOS_PROVISIONING_PROFILE_B64`

## App Store Connect API key secret

Create an App Store Connect API key and store:

- key id in `APP_STORE_CONNECT_KEY_ID`
- issuer id in `APP_STORE_CONNECT_ISSUER_ID`
- the `.p8` file contents as base64 in `APP_STORE_CONNECT_API_KEY_B64`

PowerShell example:

```powershell
[Convert]::ToBase64String(
  [Text.Encoding]::UTF8.GetBytes((Get-Content "C:\path\to\AuthKey_ABCD123456.p8" -Raw))
)
```

## Running the workflow

1. Push the repo to GitHub.
2. Open `Actions`.
3. Run `iOS TestFlight`.
4. Optionally set a changelog and external TestFlight group names.
5. Bump `version:` in `pubspec.yaml` before each new TestFlight upload.

The workflow will:

- decode release/signing/Firebase files from secrets
- install Flutter and CocoaPods on a GitHub macOS runner
- build the iOS archive through fastlane
- upload the build to TestFlight

## Repo-side release prep included here

- Bundle ID and Apple team now come from `ios/Flutter/Common.xcconfig` plus `ReleaseSecrets.xcconfig`.
- `Info.plist` now includes `NSCameraUsageDescription` for QR scanning.
- Release and debug push entitlements exist in:
  - `ios/Runner/RunnerDebug.entitlements`
  - `ios/Runner/RunnerRelease.entitlements`
- `GoogleService-Info.plist` is copied into the built app only when the file is present.

## Still required outside this repo

- A valid Apple Developer account
- A real bundle identifier registered in Apple Developer
- A distribution certificate and App Store provisioning profile
- A Firebase iOS app matching that bundle identifier
- A first successful `pod install` on macOS if you want to generate and commit `ios/Podfile.lock` for stricter reproducibility
- A successful macOS/Xcode build run, because this Windows machine cannot compile the iOS target
