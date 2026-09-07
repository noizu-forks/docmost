import Config

config :docmost_mcp,
  api_url: System.get_env("DOCMOST_API_URL", "https://docmost.noizu.com"),
  api_key: System.get_env("DOCMOST_API_KEY"),
  writes: System.get_env("DOCMOST_MCP_WRITES") == "1",
  # Session-identity auth (fork integration): the shared APP_SECRET docmost
  # signs session JWTs with; HTTP streamable transport flags/port.
  app_secret: System.get_env("DOCMOST_APP_SECRET"),
  allow_static_key: System.get_env("DOCMOST_MCP_ALLOW_STATIC_KEY") == "1",
  start_stdio:
    System.get_env("DOCMOST_MCP_STDIO", if(config_env() == :test, do: "false", else: "true")) ==
      "true",
  start_http:
    System.get_env("DOCMOST_MCP_HTTP", if(config_env() == :test, do: "false", else: "true")) ==
      "true",
  http_port: String.to_integer(System.get_env("DOCMOST_MCP_HTTP_PORT", "4000"))
