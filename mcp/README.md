# Docmost MCP

**Repo:** https://github.com/noizu-labs/docmost-mcp

An Elixir MCP server for the Docmost API — direct tools plus a writable virtual filesystem for spaces, page hierarchy, Markdown content, sharing, and page permissions.

## What

Exposes a Docmost instance (wiki) to MCP clients two ways: direct page/space/share tools (e.g. `docmost_page_share`), and a VFS where pages are `.md` files (YAML frontmatter + Markdown) and `.meta` siblings are command-oriented YAML control files for share/access state.

## Why

Docmost has no MCP interface of its own; this lets coding agents read, write, share, and permission the Noizu documentation wiki directly — and, via the VFS, do it with ordinary file-tool workflows. Writes are deliberately opt-in so the default posture against the production instance is read-only.

## Getting Started

**Configuration** — copy `.env.example` into your secret-management workflow. Required variables:

- `DOCMOST_API_URL` — instance base (defaults to `https://docmost.noizu.com`); `/api` is normalized automatically
- `DOCMOST_API_KEY` — bearer API key; never commit or print it
- `DOCMOST_MCP_WRITES=1` — opt in to all mutations (default is read-only)

**Safety warning:** the default URL is the production Noizu Docmost instance. Writes are disabled unless `DOCMOST_MCP_WRITES=1`, but set `DOCMOST_API_URL` explicitly for development and tests before enabling writes.

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix run --no-halt    # run locally; MCP over stdio
```

Set `config :docmost_mcp, start_stdio: false` when embedding the OTP app.

## How It Works

**VFS layout**

```text
/
└── engineering/
    ├── getting-started.md
    ├── getting-started.meta
    └── getting-started/
        ├── install.md
        └── install.meta
```

- Creating, overwriting, or removing a `.md` file maps to the corresponding Docmost page operation. Nested pages are represented by frontmatter (`parent`) while the filesystem also exposes child pages beneath a directory named for their parent; the parent page stays editable through its sibling `.md` file. This keeps identical child slugs under different parents unambiguous.
- **`.meta` files are command files, not round-trip documents.** Full read output includes protected identifiers and effective state; writing that output back verbatim is intentionally rejected. Write a minimal YAML command with only mutable keys:

  ```yaml
  share: public
  include_sub_pages: false
  search_indexing: false
  access: restricted
  permissions_mode: add
  permissions:
    - role: reader
      user_ids: ["00000000-0000-0000-0000-000000000000"]
  ```

- After a successful write, read the file again — a public page returns `share: "public"` plus its share `url`. Shell redirection has no stdout; the refreshed YAML comes via `cat page.meta` (or the `docmost_page_share` tool, which returns it in the same call).
- Inherited shares/restrictions are reported with a positive `*_level` and cannot be removed at a child page. Permissions are additive unless `permissions_mode: replace` is explicit. Unknown, contradictory, and read-only fields are rejected.
- Replace mode is the closest Docmost allows to a permission transaction: it validates the complete document and adds new principals before removing old ones, so a mid-request API failure can leave a safe permission superset.

## Development notes

The checkout uses the current sibling `elixir-mcp` library; `NOIZU_MCP_PATH` can override that path outside the monorepo.

## Fork integration (session-identity auth + HTTP transport)

This copy of docmost-mcp is vendored into noizu-forks/docmost via `git subtree`
(path `mcp/`). On top of the standalone service it adds:

- **Streamable HTTP transport** (`DocmostMCP.HTTP`): Bandit serves the MCP
  streamable HTTP endpoint at `/mcp` on `DOCMOST_MCP_HTTP_PORT` (default 4000).
  Stdio still works for CLI use (`DOCMOST_MCP_STDIO=true`).
- **Session-identity auth** (`DocmostMCP.Auth`, `DocmostMCP.Auth.SessionPlug`):
  requests are authenticated as the *signed-in docmost user*. The edge proxy
  forwards cookies untouched; the plug verifies the `authToken` cookie or
  `Authorization: Bearer` JWT locally (HS256, `DOCMOST_APP_SECRET` — the same
  APP_SECRET docmost signs sessions with), accepts only interactive user
  sessions (`type: "access"`), and forwards the verified JWT as Bearer on every
  Docmost REST call. Invalid/expired → `401` with a JSON-RPC error body.
- **Static-key fallback**: `DOCMOST_API_KEY` as Bearer is honored only when
  `DOCMOST_MCP_ALLOW_STATIC_KEY=1` (local/dev CLI use). A presented-but-invalid
  session credential never downgrades to the static key.
- **Container setup**: the docmost fork's `docker-compose.mcp.yml` (override
  file — upstream `docker-compose.yml` is untouched) builds this Dockerfile and
  adds a Caddy edge proxy routing `{site}/mcp*` → mcp:4000 (SSE-safe,
  unbuffered) and everything else → docmost:3000.

Local checks: `mix test`, `mix format --check-formatted`.

**Subtree sync** (run from the docmost fork root):

    git subtree pull --prefix=mcp https://github.com/noizu-labs/docmost-mcp.git develop

Fork-local modifications under `mcp/` (auth modules, HTTP transport, this
section, Dockerfile/Caddyfile) may need a small re-apply after upstream syncs —
they are all additive files except: `mix.exs` (deps), `config/runtime.exs`
(auth envs), `lib/docmost_mcp/{application,config,server}.ex`,
`lib/docmost_mcp/client/req.ex` (bearer resolution), each a few lines.
