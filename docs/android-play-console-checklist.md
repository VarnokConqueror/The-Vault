# Android Play Console Checklist

Use this checklist when preparing The Vault for Google Play rollout.

## 1. App record

- Create the Play app with package name `com.theconquerorscourt.vault`.
- Use the Android App Bundle at `build/app/outputs/bundle/release/app-release.aab`.
- Keep each upload's version code higher than the last one.

## 2. Release signing

- Copy `android/key.properties.template` to `android/key.properties`.
- Point `storeFile` at your real upload keystore.
- Run `flutter build appbundle --release`.

## 3. Privacy policy

- Host the public privacy page from `web/privacy-policy.html`.
- Keep the source text in `docs/privacy-policy.md`.
- Keep the public terms page in `web/terms-of-service.html`.
- If you are serving the web build output, run `.\tool\build_web_release.ps1` so the legal pages are copied into `build/web/`.
- Use the hosted privacy-policy URL in Play Console.

## 4. Store listing

- App name: `The Vault`
- Store listing draft: `docs/android-play-store-listing.md`
- Keep the short description within 80 characters and the full description within 4000 characters.
- Avoid claiming protections that are not live in the Android build you upload.
- Support email: use your real support inbox before submission.

## 5. Data safety review

Before filling the Google Play Data safety form, verify the current app behavior against the live build. At minimum, review:

- user-chosen profile or display name data
- contacts and group membership data
- messages, attachments, stickers, and voice notes
- app activity and crash/diagnostic data, if any third-party SDK collects it
- device or other identifiers, including notification or relay tokens
- call signaling and connection metadata

Do not mark anything as "not collected" unless the live app truly does not collect, transmit, or retain it.

Use this repo draft as your starting point:

- `docs/android-play-data-safety.md`

## 6. Testing tracks

- Internal testing is the fastest first upload path.
- If your Play developer account is a new personal account, plan for Google's closed-testing requirements before production rollout.

## 7. Pre-launch checks

- Verify sign-in or identity creation on a clean Android install.
- Verify direct messaging, group messaging, notifications, attachments, voice notes, and calls on at least two real Android devices.
- Verify app upgrade behavior from one build to the next.
- Verify account removal, app clear-data behavior, and notification opt-out behavior.
