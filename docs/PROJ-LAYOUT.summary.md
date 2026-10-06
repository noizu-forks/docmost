# Project Layout (Summary)

```
docmost-mcp/
├── lib/docmost_mcp/     # Source: server.ex, tools/, vfs/, client, mount, config
├── config/              # config.exs, runtime.exs
├── test/                # ExUnit suites + support/ (stubs, VFS conformance)
├── .github/workflows/   # ci.yml
├── .env.example         # DOCMOST_* env template (writes opt-in)
├── .tool-versions       # elixir 1.18.4-otp-28, erlang 28.5
├── mix.exs              # noizu_mcp, req, bandit, plug, jason, yaml_elixir
├── README.md
└── docs/                # PROJ-LAYOUT, PROJ-ARCH (+ summaries), arch/
```

deps/ and _build/ are gitignored Mix artifacts.
