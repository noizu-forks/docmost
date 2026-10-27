# AGENT-README

> Orientation for AI coding agents working in this repo. Human docs: README.md.

## Type

node-web

## Purpose

Docmost fork — open-source collaborative wiki and documentation software (real-time collaboration, spaces, permissions, page history, embeds).

## Stack

TypeScript. NestJS API (`apps/server`) + React/Vite client (`apps/client`), TipTap editor with hocuspocus realtime, PostgreSQL + Redis. pnpm + nx workspace.

## Dev mode

```bash
pnpm install
docker compose up -d db redis   # postgres:18 + redis:8 (docker-compose.yml)
pnpm dev                        # concurrently: client:dev (vite) + server:dev (NestJS)
```

## Ports / URLs

- Server listens on `PORT` env, default 3000 (`apps/server/src/main.ts`); docker-compose publishes `3000:3000` with `APP_URL=http://localhost:3000`.
- Vite dev server proxies `/api`, `/socket.io`, `/collab` to `APP_URL` (`apps/client/vite.config.ts`).

## Tests

```bash
pnpm --filter ./apps/client run test   # vitest run
```

## Gotchas

- License split: core is AGPL 3.0; `apps/server/src/ee`, `apps/client/src/ee`, `packages/ee` are under the Docmost Enterprise license (README § License).
- App env (`APP_URL`, `DATABASE_URL`, `REDIS_URL`, `APP_SECRET`, …) is loaded from the repo root `.env` (vite `loadEnv`), same vars as docker-compose.yml.
- pnpm-only workspace; builds go through nx (`pnpm build` → `nx run-many -t build`).
