import Config

config :docmost_mcp,
  api_url: System.get_env("DOCMOST_API_URL", "https://docmost.noizu.com"),
  api_key: System.get_env("DOCMOST_API_KEY"),
  writes: System.get_env("DOCMOST_MCP_WRITES") == "1",
  mount_token: System.get_env("DOCMOST_MCP_MOUNT_TOKEN"),
  mount_port: String.to_integer(System.get_env("DOCMOST_MCP_MOUNT_PORT", "4700"))
