# Project Architecture (Summary)

Elixir MCP server exposing a Docmost wiki as (a) direct `docmost_*` tools and (b) a writable VFS (`*.md` pages + `*.meta` command YAML, `/etc/dev` control tree). Stateless proxy over the Docmost HTTP API; only in-memory state is a monotonic `VersionStore`. Mutations gated by `DOCMOST_MCP_WRITES=1` (runtime-flippable via `/etc/dev/config/writes`).

- **Server** (`Noizu.MCP.Server`, stdio) registers `Tools.Core` (7 tools) and `VFS.Controlled` (delegates to `VFS.Backend`).
- **Client facade** behind `ClientBehaviour`; `Req` implementation; injectable stub for tests.
- **Mount** (opt-in): VFSWS WebSocket via Bandit on 127.0.0.1:4700, two-layer auth (Bearer upgrade + `vfs/auth` frame), separate token from the API key, for `mcp-mount` FUSE projection.
- **Key decisions**: read-only by default; `.meta` files are commands (write-back of full read output rejected); inherited shares immutable at children; permissions replace-mode validates then adds-before-removes; versions are ephemeral — restart forces client re-pull.
- **Stack**: Elixir 1.18/OTP 28, `noizu_mcp` (sibling elixir-mcp), Req, Bandit, Plug, Jason, yaml_elixir; GitHub Actions CI with 85% coverage threshold.
