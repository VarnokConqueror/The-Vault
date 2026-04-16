# Vault Backend Contract

This repo is the Flutter client for `The Vault`. It does not include the relay
or messaging backend. This document defines the minimum backend surface needed
to migrate the current shared-mailbox messaging model to Vault-style 1:1
device sessions.

## Scope

This contract is for:

- device registration
- prekey upload and rotation
- prekey bundle fetch
- per-device message fanout
- per-device mailbox fetch and ack
- device list and identity change detection

This contract is not yet for:

- group messaging
- sender keys
- attachment blob storage
- call signaling migration

## Client Models Already Added

The client now contains code-aligned DTOs in:

- [vault_models.dart](C:/Users/Varnok/The-Vault/lib/core/vault/vault_models.dart)
- [vault_bridge.dart](C:/Users/Varnok/The-Vault/lib/core/vault/vault_bridge.dart)

Key types:

- `VaultAddress { userId, deviceId }`
- `VaultDeviceIdentity { address, registrationId, identityPublicKeyB64 }`
- `VaultSignedPreKey { keyId, publicKeyB64, signatureB64, generatedAtMs }`
- `VaultOneTimePreKey { keyId, publicKeyB64 }`
- `VaultPreKeyBundle`
- `VaultPreKeyUpload`
- `VaultCiphertext { messageType, ciphertextB64 }`
- `VaultOutboundEnvelope { destination, ciphertext }`
- `VaultInboundEnvelope { source, ciphertext, serverTimestampMs }`

## Required Backend Concepts

- Each user can have multiple devices.
- Each device has a stable integer `deviceId`.
- Each device has its own mailbox.
- Each device publishes:
  - identity public key
  - registration id
  - one signed prekey
  - a batch of one-time prekeys
- Messages are fanned out per destination device, not per chat mailbox.
- Push should be opaque. The server should wake the device without including
  message plaintext.

## API Surface

### 1. Register Device

`POST /v1/devices/register`

Request:

```json
{
  "userId": "user-123",
  "platform": "android",
  "appVersion": "1.0.0",
  "deviceLabel": "Pixel 9 Pro XL"
}
```

Response:

```json
{
  "address": {
    "userId": "user-123",
    "deviceId": 1
  },
  "deviceMailboxId": "mbx_user-123_1",
  "created": true
}
```

Rules:

- If the device is already registered, return the existing `deviceId`.
- `deviceMailboxId` must be stable for the life of the device.

### 2. Upload Prekeys

`POST /v1/prekeys/upload`

Request body should match `VaultPreKeyUpload.toJson()`.

Response:

```json
{
  "ok": true,
  "storedOneTimePreKeys": 100,
  "minNextPreKeyCount": 25
}
```

Rules:

- Replace the current signed prekey for that device.
- Insert the provided one-time prekeys.
- Reject uploads if the identity key changes without an explicit key-change
  flow.

### 3. Fetch Device List

`GET /v1/devices/{userId}`

Response:

```json
{
  "userId": "user-456",
  "devices": [
    {
      "address": {
        "userId": "user-456",
        "deviceId": 1
      },
      "registrationId": 9911,
      "identityPublicKeyB64": "base64..."
    }
  ],
  "identityChanged": false
}
```

Rules:

- Return all active devices for the user.
- `identityChanged` should flip when the backend knows the device identity set
  has changed in a way the client must surface.

### 4. Fetch Prekey Bundle

`GET /v1/prekeys/{userId}/{deviceId}`

Response body should match `VaultPreKeyBundle.toJson()`.

Rules:

- Consume and remove one one-time prekey if available.
- If no one-time prekey is available, still return a valid bundle with
  `oneTimePreKey = null`.

### 5. Send Device Envelopes

`POST /v1/messages/send`

Request:

```json
{
  "source": {
    "userId": "user-123",
    "deviceId": 1
  },
  "messages": [
    {
      "destination": {
        "userId": "user-456",
        "deviceId": 1
      },
      "ciphertext": {
        "messageType": "prekey",
        "ciphertextB64": "base64..."
      }
    }
  ],
  "clientMessageId": "msg-123"
}
```

Response:

```json
{
  "accepted": [
    {
      "userId": "user-456",
      "deviceId": 1
    }
  ],
  "rejected": []
}
```

Rules:

- The server treats ciphertext as opaque bytes.
- The server does not inspect or transform message contents.
- Fanout is per destination device.

### 6. Fetch Device Mailbox

`GET /v1/mailboxes/{deviceMailboxId}?limit=100`

Response:

```json
{
  "mailboxId": "mbx_user-456_1",
  "envelopes": [
    {
      "envelopeId": "env-123",
      "source": {
        "userId": "user-123",
        "deviceId": 1
      },
      "ciphertext": {
        "messageType": "whisper",
        "ciphertextB64": "base64..."
      },
      "serverTimestampMs": 1770000000000
    }
  ]
}
```

Rules:

- The mailbox belongs to exactly one device.
- Ordering should be oldest-first or explicitly documented.
- Delivery should be at-least-once until acked.

### 7. Ack Device Envelopes

`POST /v1/mailboxes/{deviceMailboxId}/ack`

Request:

```json
{
  "envelopeIds": ["env-123", "env-124"]
}
```

Response:

```json
{
  "ok": true,
  "acked": 2
}
```

## Push Contract

Push registration should move from shared chat mailboxes to device mailboxes.

`POST /v1/push/register`

Request:

```json
{
  "mailboxId": "mbx_user-123_1",
  "deviceId": "user-123:1",
  "platform": "android",
  "fcmToken": "token"
}
```

Push payloads should be opaque wakeups:

```json
{
  "type": "messages_available",
  "mailboxId": "mbx_user-123_1"
}
```

They must not include message text.

## Identity Change Rules

- If a device identity key changes unexpectedly, the backend must expose that
  fact through device list and bundle fetch results.
- The client must be able to stop sending until the user accepts the change.

## Attachment Direction

Attachments should not be chunked through Vault envelopes long-term.

Preferred model:

- upload encrypted blob to object storage or relay blob storage
- send the attachment metadata and content-encryption key inside the ratcheted
  message body

## Recommended Implementation Order

1. Device registration
2. Prekey upload and fetch
3. Per-device mailbox send/fetch/ack
4. Opaque push registration
5. Identity-change detection
6. Attachment transport
7. Group messaging

## Current Client Blocker

Until the backend repo or server code is available, this client can only
scaffold the native bridge and data models. End-to-end Vault sessions cannot
be completed from this repo alone.
