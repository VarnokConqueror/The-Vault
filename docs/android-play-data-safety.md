# Android Play Data Safety

This is the conservative starting draft for The Vault's Google Play Data safety form as of `2026-04-04`.

The goal here is accuracy first. If there is any doubt, this draft favors disclosing more rather than less.

## Recommended top-level answers

- Data is encrypted in transit: `Yes`
- You can request that data is deleted: `No` for now, unless you set up and operationalize a real deletion workflow that you can actually honor end to end

## Recommended disclosed data types

| Play data type | Recommended answer | Shared | Required or optional | Why |
|---|---|---|---|---|
| `Name` | `Yes` | `No` | `Required` | The app maintains and transmits a display name / handle for messaging identity. |
| `User IDs` | `Yes` | `No` | `Required` | The app creates and uses user/device-facing identifiers for messaging, push registration, and relay routing. |
| `Contacts` | `Yes` | `No` | `Optional` | Users can create and manage in-app contacts and direct/group relationships. |
| `Other messages` | `Yes` | `No` | `Optional` | The app sends and receives instant message content in chats. |
| `Photos` | `Yes` | `No` | `Optional` | Users can choose photos to send in chat attachments. |
| `Videos` | `Yes` | `No` | `Optional` | Users can choose videos to send in chat attachments. |
| `Voice or sound recordings` | `Yes` | `No` | `Optional` | Users can record and send voice notes. |
| `Files and docs` | `Yes` | `No` | `Optional` | Users can send general file attachments and documents. |
| `Other user-generated content` | `Yes` | `No` | `Optional` | Users can submit open-ended anonymous feedback through the in-app feedback form. |
| `Diagnostics` | `Yes` | `No` | `Optional` | Users can optionally attach app diagnostics when sending feedback. |
| `Device or other IDs` | `Yes` | `No` | `Required` | Firebase Installations IDs, push tokens, Vault device IDs, and related relay identifiers are used for delivery and registration. |

## Recommended purposes

Use these purposes where the Play form asks why the app collects a disclosed data type:

- `App functionality`
- `Account management` for identity-related fields if you want to be extra explicit
- `Analytics` only for optional diagnostics or operational troubleshooting data that you actually review

Do not select:

- `Advertising or marketing`
- `Fraud prevention, security, and compliance` unless you add a real flow that actually uses the data for that purpose
- `Developer communications` unless you start using stored user data to directly contact users
- `Personalization` unless you add actual personalized content logic that depends on disclosed data

## Recommended "not shared" position

Recommended answer for the listed data types: `No`, not shared.

Why:

- Google Play treats transfers to service providers processing data on your behalf differently from third-party sharing.
- The Vault currently uses first-party infrastructure plus service-provider style components like Firebase Cloud Messaging.
- Do not mark data as shared unless you intentionally send app data to unrelated third parties, ad networks, or other apps.

## Recommended "not collected" categories

Assuming the current Android build remains as-is, you should leave these as not collected:

- `Location`
- `Email address`
- `Phone number`
- `Address`
- `Payment info`
- `Purchase history`
- `Health and fitness`
- `Calendar`
- `Web browsing`
- `Installed apps`
- `Crash logs` from an automatic crash SDK
- `In-app search history`
- `SMS or MMS`
- `Emails`
- `Advertising ID`

## Important caveat about end-to-end encrypted chat data

Google Play says user data sent off-device can be out of scope for collection disclosure if it is truly end-to-end encrypted and unreadable to the developer or any intermediary.

The Vault may eventually be able to rely on that narrower interpretation for chat payloads, but only after you do a strict audit of every currently shipped message, media, backup, import, feedback, push, and support path.

For first submission, this document intentionally takes the safer route and discloses chat and attachment content conservatively.

## Why this draft matches the current app

- The app has in-app identity, direct chats, and groups.
- The app supports photos, videos, voice notes, and file attachments.
- The app supports anonymous feedback with optional diagnostics.
- The app uses Firebase Messaging, which brings Firebase Installations into the dependency graph.

## Final review checklist before you submit the form

- Re-check the live Android build, not just local code.
- Re-check every included SDK and transitive SDK.
- Re-check the current feedback flow and whether diagnostics are still optional.
- Re-check whether any old or fallback message path can still send readable server-side payloads.
- Re-check whether you have implemented a real deletion workflow before answering `Yes` to deletion.
