# moCODE Monorepo

This repo now keeps the Flutter client and Bun server under a single workspace:

- `apps/mobile`: Flutter app
- `apps/server`: Bun + Hono API

## Setup

```bash
bun install
bun run mobile:pub:get
```

Copy the server env file before starting the API:

```bash
cp apps/server/.env.example apps/server/.env
```

## Root commands

```bash
bun run dev
bun run lint
bun run cli -- start
bun run cli -- status
bun run cli -- pair
bun run cli -- agents list
bun run cli -- acp list
bun run cli -- activate
bun run db:push
bun run db:generate
bun run mobile:codegen
bun run mobile:run
bun run mobile:apk
bun run mobile:aab
```

`bun run dev` starts the server from the repo root. `bun run lint` checks the server TypeScript setup and runs `flutter analyze` for the mobile app.

For a direct executable during local development:

```bash
cd apps/cli
bun link
mocode start
mocode pair
mocode activate
```
