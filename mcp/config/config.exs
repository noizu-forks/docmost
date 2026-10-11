import Config

config :docmost_mcp,
  start_stdio: config_env() != :test,
  client: DocmostMCP.Client.Req,
  # The filesystem mount is opt-in: no token, no listener (and never a default
  # token under :test).
  mount_token: nil,
  mount_port: 4700
