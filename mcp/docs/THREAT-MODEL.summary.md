# Threat Model (Summary)

Stateless proxy to the production Docmost wiki. Entry points: MCP stdio (trusted local client) and opt-in localhost VFSWS mount (Bearer + `vfs/auth` frame, 127.0.0.1 only, token separate from API key). Egress: Docmost API over HTTPS bearer. No local stores.

- Writes to production gated by `DOCMOST_MCP_WRITES` (default off; runtime toggle via `/etc/dev/config/writes`).
- VFS paths strict-validated (no `..`, segment allowlist); `.meta` YAML commands strictly allow-listed.
- Register: 11 entries — 8 mitigated, 1 partial (runtime writes toggle, T-002), 2 open/accepted: prompt-injection via wiki content consumed by agents (T-004) and no local audit trail (T-008, Docmost is system of record).
- Residual: mount-token holder on-host can enable writes and mutate prod; default API URL is production — pin `DOCMOST_API_URL` before enabling writes.
- Supply chain: pinned deps; sibling `elixir-mcp` path dep inside monorepo trust boundary.
