# Project Architecture — summary

The `noizu-forks/docmost` fork of Docmost is a pnpm + Nx monorepo: a
**NestJS/Fastify API** (`apps/server`), a **React/Vite SPA** (`apps/client`),
and shared **TypeScript packages** (`editor-ext`, `base-formula`). Document
editing is multiplayer via **TipTap/ProseMirror + Yjs CRDTs** synchronised by a
**Hocuspocus** collaboration server. **PostgreSQL** (through **Kysely**) is the
store; **Redis** backs caching, the BullMQ queue, and the WebSocket adapter.

The fork's only addition is an **Elixir MCP service** vendored in `mcp/`
(`git subtree` of `noizu-labs/docmost-mcp`) behind a Caddy edge in
`docker-compose.mcp.yml`. It authenticates as the signed-in Docmost user
(shared APP_SECRET, forwards the session JWT) and acts through Docmost's own
REST + permissions. All fork code is additive; upstream files are untouched.

**Core components:** REST API, JWT auth + CASL authorization, Hocuspocus
collaboration, realtime WS gateway, Kysely persistence, integrations (storage,
mail, queue, encryption, export/import, audit, throttle, telemetry), community
vs optional enterprise (`apps/server/src/ee` submodule), shared packages,
client SPA, MCP service.

**Data flow:** edits → Hocuspocus Yjs merge → `pages` (`ydoc`, flattened
`content`/`text_content`, `tsvector`) ; API requests → JWT validate → CASL
authorize → Kysely → Postgres; heavy work → BullMQ; MCP → verify JWT locally →
forward Bearer → REST as user.

**Stack:** NestJS 11 / Fastify 5, PostgreSQL + Kysely, Redis + BullMQ,
Hocuspocus 4 + Yjs + TipTap 3, React + Vite + Mantine + TanStack, storage
local/S3/Azure, mail SMTP/Postmark, OAuth2/Stripe/AI/SCIM/SIEM, Elixir MCP.
Build: pnpm 11 + Nx 23 + Docker multi-arch.

Full detail: [PROJ-ARCH.md](PROJ-ARCH.md) · components↔dirs: [PROJ-LAYOUT.md](PROJ-LAYOUT.md)
