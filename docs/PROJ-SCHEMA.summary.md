# Project Schema (Summary)

No relational store — stateless proxy over the Docmost HTTP API. Structured data:

- **MCP tools** (`lib/docmost_mcp/tools/core.ex`): `docmost_spaces_list`, `docmost_pages_list(space_id*)`, `docmost_page_get(page_id*)` (read-only); `docmost_page_create(space_id*, title*, content, parent_page_id)`, `docmost_page_update(page_id*, content*, title)`, `docmost_page_delete(page_id*, confirm)` (destructive), `docmost_page_share(page_id*, share: public|private, include_sub_pages, search_indexing)` — all mutations gated by `DOCMOST_MCP_WRITES=1`.
- **VFS page file** `*.md`: YAML frontmatter (`id`, `title`, `parent`, `space`, `updated` — read-only) + Markdown body.
- **VFS meta file** `*.meta`: writable keys `share, include_sub_pages, search_indexing, access, permissions, permissions_mode`; read-only keys `id, page_id, url, share_level, access_level, effective_share, effective_access`; unknown keys rejected.
- **Control tree** `/etc/dev/**`: runtime introspection + `writes` toggle.
- **Env/config**: `DOCMOST_API_URL` (default `https://docmost.noizu.com`), `DOCMOST_API_KEY`, `DOCMOST_MCP_WRITES` (default off), `DOCMOST_MCP_MOUNT_TOKEN`, `DOCMOST_MCP_MOUNT_PORT` (4700).
- **In-memory**: `VersionStore` GenServer — `%{epoch, paths: %{path => {fingerprint, version}}}`; monotonic versions, restart bumps epoch, nothing persisted.
