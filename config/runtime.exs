import Config

config :docmost_mcp,
  api_url: System.get_env("DOCMOST_API_URL", "https://docmost.noizu.com"),
  api_key: System.get_env("DOCMOST_API_KEY"),
  writes: System.get_env("DOCMOST_MCP_WRITES") == "1"
