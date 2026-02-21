# moCODE API Documentation

Base URL: `https://your-server.com`

## Table of Contents

- [Health](#health)
- [Early Access](#early-access)
- [Authentication](#authentication)
- [Billing](#billing)
- [ASR (Speech-to-Text)](#asr-speech-to-text)
- [Account](#account)

---

## Health

### GET /api/health

Health check endpoint.

**Response:**

```json
{
  "ok": true,
  "service": "mecode-server"
}
```

---

## Early Access

### POST /api/early-access

Subscribe to early access.

**Headers:**
| Header | Value |
|--------|-------|
| Content-Type | application/json |

**Body:**

```json
{
  "email": "user@example.com"
}
```

**Response (200):**

```json
{
  "ok": true,
  "message": "You're on the list!"
}
```

**Response (400):** Invalid email

---

## Authentication

All protected endpoints require Firebase authentication.

**Headers:**
| Header | Value |
|--------|-------|
| Authorization | Bearer `<firebase-id-token>` |

### GET /api/v1/auth/me

Get current authenticated user.

**Response (200):**

```json
{
  "user": {
    "id": "uuid",
    "firebaseUid": "firebase-uid",
    "email": "user@example.com",
    "displayName": "John Doe"
  },
  "access": {
    "oneTimeUnlocked": true,
    "paidAt": "2024-01-15T10:30:00Z"
  }
}
```

---

## Billing

### POST /api/v1/billing/webhook

Webhook endpoint for Dodo Payments. Receives payment events.

**Headers:**
| Header | Value |
|--------|-------|
| webhook-id | string |
| webhook-signature | string |
| webhook-timestamp | string |

### POST /api/v1/billing/create-checkout-session

Create a checkout session for one-time unlock.

**Headers:**
| Header | Value |
|--------|-------|
| Authorization | Bearer `<firebase-id-token>` |
| Content-Type | application/json |

**Body:**

```json
{
  "quantity": 1
}
```

**Response (200):**

```json
{
  "sessionId": "session_xxx",
  "checkoutUrl": "https://checkout.dodopayments.com/xxx",
  "reused": false
}
```

### GET /api/v1/billing/status

Get user's billing/entitlement status.

**Headers:**
| Header | Value |
|--------|-------|
| Authorization | Bearer `<firebase-id-token>` |

**Response (200):**

```json
{
  "oneTimeUnlocked": true,
  "provider": "dodopayments",
  "paymentId": "pay_xxx",
  "paidAt": "2024-01-15T10:30:00Z"
}
```

---

## ASR (Speech-to-Text)

### POST /api/v1/asr/transcribe

Transcribe audio using Groq's Whisper model.

**Headers:**
| Header | Value |
|--------|-------|
| Authorization | Bearer `<firebase-id-token>` |
| Content-Type | multipart/form-data |

**Form Data:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| audio | file | Yes | Audio file (mp3, wav, ogg, webm, m4a, aac) |
| language | string | No | Language code (e.g., "en", "es") |

**Response (200):**

```json
{
  "text": "Transcribed text here",
  "segments": [
    {
      "text": "Hello world",
      "start": 0.0,
      "end": 1.5
    }
  ],
  "words": [
    {
      "word": "Hello",
      "start": 0.0,
      "end": 0.5,
      "confidence": 0.95
    }
  ],
  "language": "en",
  "duration": 5.2
}
```

**Response (400):**

```json
{
  "error": "Audio file is required"
}
```

```json
{
  "error": "Invalid audio file type",
  "details": "Received: video/mp4. Allowed: audio/mpeg, audio/mp3, audio/wav..."
}
```

**Response (401):** Unauthorized (invalid or missing token)

---

## Account

### POST /api/v1/account-deletion-request

Request account deletion.

**Headers:**
| Header | Value |
|--------|-------|
| Authorization | Bearer `<firebase-id-token>` |
| Content-Type | application/json |

**Body:**

```json
{
  "email": "user@example.com"
}
```

**Response (200):**

```json
{
  "ok": true
}
```

---

## Error Responses

All endpoints may return the following error responses:

| Status | Description                             |
| ------ | --------------------------------------- |
| 400    | Bad Request - Invalid payload           |
| 401    | Unauthorized - Invalid or missing token |
| 500    | Internal Server Error                   |
