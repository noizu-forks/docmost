# Project Layout

Elixir MCP server for the Docmost API — direct tools plus a writable VFS over spaces/pages.
Repo: https://github.com/noizu-labs/docmost-mcp

```
docmost-mcp/
├── lib/docmost_mcp/            # Application source
│   ├── application.ex          #   OTP supervision; stdio MCP server entry
│   ├── server.ex               #   MCP server: tool registration & dispatch
│   ├── tools/                  #   MCP tool implementations
│   │   └── core.ex             #     Direct page/space/share/permission tools
│   ├── vfs/                    #   Virtual filesystem projection
│   │   ├── backend.ex          #     Spaces/pages as dirs + .md files + .meta YAML
│   │   ├── control.ex          #     Command-oriented .meta control files
│   │   ├── meta_file.ex        #     .meta YAML encoding/decoding
│   │   ├── page_file.ex        #     Page = YAML frontmatter + Markdown
│   │   └── path.ex             #     VFS path parsing/resolution
│   ├── mount.ex                #   Local FS mount (mcp-mount over WebSocket)
│   ├── client.ex               #   Docmost API client facade
│   ├── client/req.ex           #   Req-based HTTP implementation
│   ├── client_behaviour.ex     #   Client behaviour (stub/test doubles)
│   ├── config.ex               #   Runtime config (URL, API key, writes flag)
│   ├── normalize.ex            #   URL/response normalization
│   ├── version_store.ex        #   Stable monotonic VFS versions
│   └── error.ex                #   Error types
├── config/
│   ├── config.exs              # Compile-time config
│   └── runtime.exs             # Runtime config from env (writes flag, mount)
├── test/                       # ExUnit suites + VFS conformance harness
│   └── support/                #   StubClient, TestClient, VFS conformance specs
├── .github/workflows/ci.yml    # CI: fmt check, compile --warnings-as-errors, test
├── .env.example                # Copy to secret management — DOCMOST_* vars
├── .formatter.exs              # mix format config
├── .tool-versions              # elixir 1.18.4-otp-28 / erlang 28.5 (asdf/mise)
├── mix.exs                     # Deps: noizu_mcp, req, bandit, plug, jason, yaml_elixir
├── mix.lock
├── README.md                   # Start here — config, VFS layout, safety notes
└── docs/                       # This documentation
    ├── PROJ-LAYOUT.md
    ├── PROJ-LAYOUT.summary.md
    ├── PROJ-ARCH.md
    ├── PROJ-ARCH.summary.md
    └── arch/
```

`deps/` and `_build/` are gitignored Mix artifacts; `.claude/worktrees/` is local-only.

## Key Files Requiring Setup

| File | Action |
|------|--------|
| `.env.example` | Source for secret management — set `DOCMOST_API_URL`, `DOCMOST_API_KEY`, `DOCMOST_MCP_WRITES` (writes default **off**), optional mount token/port |
