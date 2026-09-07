# FORK.md — noizu-forks/docmost fork integration notes

This fork of docmost/docmost carries in-tree integrations on top of upstream.
Each integration is structured so future upstream merges stay conflict-free:
**all new code lives in new paths; upstream files are never modified**.

## Integrations in this fork

| Branch/PR | Feature | Paths |
|---|---|---|
| `feature/mcp-service` | MCP service (`{site}/mcp`, session-identity auth) | `mcp/` (subtree), `docker-compose.mcp.yml`, `FORK.md` (this file) |

## MCP service (`mcp/` subtree)

An Elixir MCP server (noizu-labs/docmost-mcp) vendored via `git subtree` that
exposes docmost spaces/pages/shares to MCP clients, served at **`{site}/mcp`**
over MCP streamable HTTP, authenticated as the **signed-in docmost user**.

### Run it

```bash
docker compose -f docker-compose.yml -f docker-compose.mcp.yml up
```

- `proxy` (Caddy) listens on :80 (set `PROXY_PORT` to change) and replaces the
  upstream app's exposed port via the override (`ports: !override []` on
  `docmost`).
- `{site}/mcp*` → `mcp:4000` (streamable HTTP; unbuffered/SSE-safe). Paths are
  passed through unrewritten — the MCP endpoint is exactly `/mcp`.
- `/*` → `docmost:3000` (upstream app, unchanged).
- `mcp` builds from the `mcp/` subtree (`mcp/Dockerfile`, fork-local).

### Session-identity auth

Docmost sessions are HS256 JWTs (`{sub, email, workspaceId, type: "access"}`)
in the `authToken` cookie, signed with `APP_SECRET`. The override passes the
same value to the mcp service as `DOCMOST_APP_SECRET`. The mcp service:

1. verifies the session JWT locally (signature + expiry — no introspection),
   from the `authToken` cookie (forwarded untouched by Caddy) or
   `Authorization: Bearer`;
2. accepts only interactive user sessions (`type: "access"` — API-key/collab/
   OAuth tokens are rejected);
3. forwards the verified JWT as `Authorization: Bearer` on every Docmost REST
   call, so all tool operations run as the signed-in user with docmost's own
   permission checks;
4. answers invalid/expired credentials with `401` + JSON-RPC error.

The static shared `DOCMOST_API_KEY` still works for local CLI use, but only
when `DOCMOST_MCP_ALLOW_STATIC_KEY=1` is set on the mcp service. A presented-
but-invalid session credential never falls back to the static key. Writes
remain gated by `DOCMOST_MCP_WRITES=1`. The override file carries a commented
`DATABASE_URL` block showing how to grant the mcp service direct Postgres
access later (intentionally not enabled).

### Upstream-merge strategy

- `git subtree add` landed upstream untouched at `mcp/`; fork-local additions
  under `mcp/` are additive files (auth plug, HTTP transport, Dockerfile,
  Caddyfile, tests) plus a handful of small line-scoped edits — all confined to
  the subtree, so upstream docmost sees nothing.
- Upstream docmost files modified: **none.**
- Future docmost upstream merges cannot conflict with these paths (`mcp/`,
  `docker-compose.mcp.yml`, `FORK.md` do not exist upstream).
- Sync the MCP service from its upstream:

```bash
git subtree pull --prefix=mcp https://github.com/noizu-labs/docmost-mcp.git develop
```

  If that pull conflicts inside `mcp/`, the fork-local edits listed in
  `mcp/README.md` ("Fork integration" section) are what to re-apply.
