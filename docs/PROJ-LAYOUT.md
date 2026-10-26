# Project Layout — Docmost fork

A navigable map of this checkout. This repo is the **`noizu-forks/docmost` fork**
of the upstream open-source Docmost wiki. It is a **pnpm + Nx monorepo** holding
the upstream application (NestJS/Fastify server, React/Vite client, shared
packages) plus one fork-local integration: a vendored **Elixir MCP service** in
`mcp/` (a `git subtree` of `noizu-labs/docmost-mcp`).

Upstream files are never modified for fork integrations; all new fork code is
additive in new paths (`mcp/`, `docker-compose.mcp.yml`, `FORK.md`). See
`FORK.md` for the merge strategy.

```
docmost/
├── apps/
│   ├── server/                 # NestJS + Fastify API + collaboration server
│   └── client/                 # React + Vite SPA
├── packages/
│   ├── editor-ext/             # Shared Tiptap editor extensions
│   ├── base-formula/           # Formula (spreadsheet-style) evaluator
│   └── ee/                     # Enterprise-license marker (LICENSE only)
├── mcp/                        # Fork-local Elixir MCP service (git subtree)
├── patches/                    # pnpm patched dependencies
├── .github/workflows/          # release + mcp-image-smoke CI
├── docker-compose.yml          # Upstream app + Postgres + Redis
├── docker-compose.mcp.yml      # Fork override: Caddy edge + mcp service
├── FORK.md                     # Fork integration notes (start here for fork)
├── README.md                   # Upstream feature overview + license split
├── package.json                # Root workspace scripts (Nx)
├── pnpm-workspace.yaml         # Workspace globs + patched deps
├── nx.json                     # Nx target orchestration/cache
├── Dockerfile                  # Multi-stage app image build
├── crowdin.yml                 # Localization source config
├── .env.example               # Environment template — copy and fill
├── .dockerignore              # Docker build ignore list
└── .gitmodules                # apps/server/src/ee → docmost/ee submodule
```

## Directory detail

### apps/server/ — NestJS API

Home of the HTTP API (`main.ts` bootstraps Nest on Fastify under a global
`api` prefix) and the real-time collaboration server. See
`apps/server/src/`:

- `core/` — feature modules (the bulk of the app): `auth`, `page`, `space`,
  `group`, `comment`, `attachment`, `share`, `search`, `workspace`, `user`,
  `session`, `notification`, `watcher`, `favorite`, `label`, `public-space`,
  `casl` (authorization). One directory per domain.
- `database/` — Kysely setup: `migrations/` (52 ordered migration files),
  `repos/`, `services/`, `types/`, `migrate.ts` (CLI runner).
- `integrations/` — cross-cutting infra: `storage` (local/S3/Azure),
  `mail`/`transactional`, `redis`, `queue` (BullMQ), `encryption`, `export`,
  `import`, `audit`, `throttle`, `telemetry`, `security`, `environment`.
- `collaboration/` — Hocuspocus/Yjs server extensions, processors, persistence.
- `ws/` — WebSocket gateway + Redis adapter for real-time tree updates.
- `community/` — AGPL/community feature set (api-key fallback, shares, spaces).
- `common/` — guards, decorators, interceptors, middlewares, helpers,
  validators, logger, and `features.ts` (feature-flag manifest).
- `ee/` — **git submodule** (`apps/server/src/ee` → `docmost/ee`). Enterprise
  server code; not present when the submodule is uninitialized. AGPL core must
  build without it (guarded dynamic `require`).

### apps/client/ — React SPA

- `src/features/` — per-domain UI (page, editor, space, comment, share, search,
  websocket, workspace, …); the largest area (~460 files).
- `src/components/` — shared UI components (~77 files).
- `src/pages/`, `src/hooks/`, `src/lib/`, `src/pages/`, `src/i18n.ts`,
  `src/theme.ts`, `src/App.tsx`, `src/main.tsx` (entry).
- `src/ee/` — Enterprise client code (present in-tree, ~361 files), licensed
  under `src/ee/LICENSE`.

### packages/

- `editor-ext/` — Tiptap editor extensions shared by client and server export
  (the biggest package, ~130 source files).
- `base-formula/` — a formula/expression evaluator (parser, tokenizer, graph,
  functions) used by the "base" (database-style table) feature.
- `ee/` — holds only the Enterprise `LICENSE`; a registration point.

### mcp/ — Fork-local Elixir MCP service

A `git subtree` of `noizu-labs/docmost-mcp`. Own `mix.exs`, `config/`,
`lib/docmost_mcp/` (~19 modules: MCP server, tools, VFS, auth, client),
`test/` (~27 test files), `Dockerfile`, `Caddyfile`, and `docs/` (that
sub-project's own architecture/layout/schema/threat docs). MCP over streamable
HTTP on `:4000`, authenticated as the signed-in Docmost user via the shared
APP_SECRET. Not built as part of the Node workspace.

### .github/workflows/

- `release.yml` — multi-arch (amd64/arm64) Docker image build + push on `v*`
  tags, using a GitHub App token to check out the `ee` submodule.
- `mcp-image-smoke.yml` — manual post-push guard that pulls the pushed `mcp`
  image from `ops.noizu.com` and boots it on `linux/amd64`.

## Key files requiring setup

| File | Action |
|------|--------|
| `.env` | Copy from `.env.example`; set `APP_SECRET` (≥32 chars), `DATABASE_URL`, `REDIS_URL` |
| `APP_SECRET` | Shared HS256 signing key — also passed to the MCP service as `DOCMOST_APP_SECRET` when using the MCP override |
| `apps/server/src/ee` | `git submodule update --init` to pull Enterprise server code (optional) |
| `docker-compose.mcp.yml` | Only needed for the MCP-enabled stack (`-f docker-compose.yml -f docker-compose.mcp.yml`) |

Generated/ignored and intentionally omitted: `node_modules/`, `dist/`, `.nx/`,
`data/`, `coverage/`, `.env*` (secrets).
