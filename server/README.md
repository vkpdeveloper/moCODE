# mecode server

Hono + Bun API for Vercel with Firebase Google auth, Dodo Payments one-time checkout, and Drizzle/Postgres persistence.

## 1) Setup

```bash
cd server
bun install
cp .env.example .env
```

Fill `.env` with:

- Postgres `DATABASE_URL`
- Dodo credentials (`DODO_PAYMENTS_API_KEY`, `DODO_WEBHOOK_SECRET`)
- Firebase Admin credentials (`FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`)

## 2) Database

```bash
bun run db:push
```

## 3) Run local

```bash
bun run dev
```

`bun run dev` validates env vars first and then starts the server.

To validate env vars during build/typecheck:

```bash
bun run build
```

Server listens on `http://localhost:3000` locally and exposes:

- `GET /api/health`
- `GET /api/v1/auth/me` (Firebase bearer token)
- `GET /api/v1/billing/status` (Firebase bearer token)
- `POST /api/v1/billing/create-checkout-session` (Firebase bearer token)
- `POST /api/v1/billing/webhook` (Dodo webhook)

## 4) Deploy to Vercel (Bun runtime)

- Keep `server/vercel.json` with `"bunVersion": "1.x"`
- Set project root to `server`
- Configure env vars from `.env.example`

## Notes on one-time access

This integration stores a single entitlement per user (`entitlements.user_id` is unique). Once a successful payment arrives via webhook, `one_time_unlocked` becomes `true` and access remains enabled.
