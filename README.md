# Docmost MCP

An Elixir MCP server for the Docmost API, with direct tools and a writable
virtual filesystem for spaces, page hierarchy, Markdown content, sharing, and
page permissions.

## Configuration

Copy `.env.example` into your secret-management workflow. Required variables:

- `DOCMOST_API_URL` — instance base (defaults to `https://docmost.noizu.com`); `/api` is normalized automatically
- `DOCMOST_API_KEY` — bearer API key; never commit or print it
- `DOCMOST_MCP_WRITES=1` — opt in to all mutations (default is read-only)

**Safety warning:** the default URL is the production Noizu Docmost instance.
Writes are disabled unless `DOCMOST_MCP_WRITES=1`, but you should still set
`DOCMOST_API_URL` explicitly for development and tests before enabling writes.

Run locally with `mix run --no-halt`. The OTP application starts MCP over
stdio. Set `config :docmost_mcp, start_stdio: false` when embedding it.

## VFS layout

```text
/
└── engineering/
    ├── getting-started.md
    ├── getting-started.meta
    └── getting-started/
        ├── install.md
        └── install.meta
```

Page files contain YAML frontmatter and Markdown. Creating, overwriting, or
removing a `.md` file maps to the corresponding Docmost page operation.
Nested Docmost pages remain represented by frontmatter (`parent`) while the
filesystem also exposes child pages beneath a directory named for their parent.
The parent page remains editable through its sibling `.md` file. This keeps
identical child slugs under different parents unambiguous.

The `.meta` sibling is synthetic YAML. Read it for effective share/access
state. Write only mutable keys:

Meta files are command-oriented control files, not conventional round-trip
documents. Their full read output includes protected identifiers and effective
state; writing that output back verbatim is intentionally rejected. Write a
minimal YAML command containing only the mutable keys below.

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

After a successful write, read the file again. A public page includes:

```yaml
share: "public"
url: "https://docs.example.com/share/…/p/untitled-…"
```

Shell redirection itself has no stdout (`printf 'share: public\n' > page.meta`);
the refreshed YAML is available via `cat page.meta`. The direct
`docmost_page_share` MCP tool returns the YAML in the same call.

Inherited shares and restrictions are reported with a positive `*_level` and
cannot be removed at a child page. Permissions are additive unless
`permissions_mode: replace` is explicit. Unknown, contradictory, and
read-only fields are rejected.

Docmost does not expose a transaction spanning permission calls. Replace mode
validates the complete document and adds new principals before removing old
ones. A mid-request API failure can therefore leave a safe permission superset.

## Development

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

The checkout uses the current sibling `elixir-mcp` library. `NOIZU_MCP_PATH`
can override that path outside the monorepo.
