# Project Layout — summary

`noizu-forks/docmost` fork of upstream Docmost: pnpm + Nx monorepo.
All new code is additive (fork integrations never modify upstream paths).

```
docmost/
├── apps/
│   ├── server/        # NestJS + Fastify API + Hocuspocus collaboration
│   │   └── src/{core,database,integrations,collaboration,ws,community,common,ee*}
│   ├── client/        # React + Vite SPA (features/, components/, ee/)
├── packages/
│   ├── editor-ext/    # Tiptap editor extensions
│   ├── base-formula/  # formula evaluator
│   └── ee/            # Enterprise LICENSE only
├── mcp/               # fork-local Elixir MCP service (git subtree)
├── patches/           # pnpm patched deps
├── .github/workflows/ # release.yml, mcp-image-smoke.yml
├── docker-compose.yml       # app + Postgres + Redis (upstream)
├── docker-compose.mcp.yml   # fork override: Caddy edge + mcp
├── FORK.md            # fork integration notes
├── README.md          # upstream overview + license split
├── package.json       # root Nx scripts
├── pnpm-workspace.yaml
├── nx.json
├── Dockerfile
├── crowdin.yml
├── .env.example       # env template (APP_SECRET, DATABASE_URL, REDIS_URL)
├── .dockerignore
└── .gitmodules        # apps/server/src/ee -> docmost/ee (enterprise submodule)
```

* `apps/server/src/ee` is a git submodule (enterprise, optional).
* `mcp/` is a subtree of `noizu-labs/docmost-mcp` with its own docs.
* Generated/ignored: `node_modules/`, `dist/`, `.nx/`, `data/`, `.env*`.

Full detail: [PROJ-LAYOUT.md](PROJ-LAYOUT.md)
