# Project Schema

Data schema reference for `docmost-mcp`. This service has **no relational store** — it is a stateless proxy over the Docmost HTTP API. The structured data in this repo is: MCP tool contracts, VFS file formats, runtime config, and one in-memory GenServer. Each is documented below. Source map: see [PROJ-LAYOUT.md](PROJ-LAYOUT.md).

## MCP Tool Contracts (`lib/docmost_mcp/tools/core.ex`)

Direct tools registered on the MCP server. All inputs are flat objects; outputs are JSON (pages/content as Markdown strings, meta as canonical YAML strings).

| Tool | Input | Output | Notes |
|------|-------|--------|-------|
| `docmost_spaces_list` | — | `{spaces: [...]}` | read-only |
| `docmost_pages_list` | `space_id: string (req)` | `{pages: [...]}` | read-only; page hierarchy |
| `docmost_page_get` | `page_id: string (req)` | Markdown content | read-only |
| `docmost_page_create` | `space_id*`, `title*`, `content=""`, `parent_page_id?` | created page | writes-gated |
| `docmost_page_update` | `page_id*`, `content*`, `title?` | updated page | writes-gated; `operation: replace` |
| `docmost_page_delete` | `page_id*`, `confirm=false` | `{ok: true}` | writes-gated + `destructive_hint`; no-op errors unless `confirm=true`; soft-delete |
| `docmost_page_share` | `page_id*`, `share: enum(public/private)*`, `include_sub_pages=false`, `search_indexing=false` | canonical meta YAML | writes-gated; inherited shares cannot be removed |

`*` = required. Writes-gated tools return an error unless `DOCMOST_MCP_WRITES=1`.

## VFS File Formats (`lib/docmost_mcp/vfs/`)

Page entries are named `<name>.md` / `<name>.meta` where `<name>` is the
kebab-cased page title (collision between siblings appends a short-id suffix,
e.g. `notes-222222`); path segments also resolve by page slug or id.

### Page file — `<path>/<name>.md`

YAML frontmatter + Markdown body, produced by `PageFile.encode/1` and parsed by `PageFile.decode/1`:

```yaml
---
id: "<uuid>"          # Docmost page id
title: "<page title>"
parent: "<uuid>"      # parentPageId, omitted at space root
space: "<uuid>"       # spaceId
updated: "<timestamp>" # updatedAt
---
<Markdown content>
```

Frontmatter keys are **read-only** identity metadata; edits to content below the second `---` update the page.

### Meta control file — `<path>/<name>.meta`

Command-oriented YAML beside each page. Two disjoint key sets (`MetaFile`):

| Kind | Keys | Meaning |
|------|------|---------|
| writable | `share`, `include_sub_pages`, `search_indexing`, `access`, `permissions`, `permissions_mode` | Applying the YAML mutates remote state |
| read-only | `id`, `page_id`, `url`, `share_level`, `access_level`, `effective_share`, `effective_access` | Computed state; writing them → `erofs` |

Unknown keys are rejected (`eio`). `permissions` entries carry role (`reader`/`writer`) plus user/group identity; `grant_id` is stripped on encode. Validation: page ids match UUID v1–5 shape.

### Control tree — `/etc/dev/**`

Composed via `VFS.Controlled` on top of the real backend. Serves runtime introspection and the `writes` toggle — the same flag as `DOCMOST_MCP_WRITES`, mutable at runtime through the mount (`Config.set_writes!/1`).

## Config / Env Schema (`config/runtime.exs`)

Single `:docmost_mcp` OTP app env, populated from environment:

| Env var | App env key | Type | Default | Notes |
|---------|-------------|------|---------|-------|
| `DOCMOST_API_URL` | `api_url` | string | `https://docmost.noizu.com` | `/api` normalized automatically |
| `DOCMOST_API_KEY` | `api_key` | string | nil | bearer token; never commit/print |
| `DOCMOST_MCP_WRITES` | `writes` | boolean (`"1"` → true) | `false` | gates every mutation incl. VFS writes & sharing |
| `DOCMOST_MCP_MOUNT_TOKEN` | `mount_token` | string | nil | mount auth; separate from API key |
| `DOCMOST_MCP_MOUNT_PORT` | `mount_port` | integer | `4700` | mcp-mount WebSocket listener |

Additional app env (not env-sourced): `client` (injected client module — stub/test doubles), `req_options` (HTTP opts), `start_stdio` (`config.exs`; set `false` when embedding).

## In-Memory State — `VersionStore` (GenServer)

Stable monotonic version numbers for remote VFS representations, so clients can distinguish "changed upstream" from "renumbered locally":

| Field | Shape | Purpose |
|-------|-------|---------|
| `epoch` | positive integer (boot wall-clock seconds, `max(1, …)`) | floor for versions issued this boot |
| `paths` | `%{path => {fingerprint, version}}` | last-seen content fingerprint per path |

Rules: same fingerprint → same version; changed fingerprint → version+1; fresh path → boot epoch (so a restart forces clients to re-pull); `reset/0` bumps the epoch past everything previously issued. State is process-only — nothing persists.
