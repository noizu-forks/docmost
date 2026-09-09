import Config

config :docmost_mcp, start_stdio: config_env() != :test, client: DocmostMCP.Client.Req
