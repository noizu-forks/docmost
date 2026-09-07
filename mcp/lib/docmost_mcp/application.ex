defmodule DocmostMCP.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # The MCP server supervision tree must run for HTTP sessions to spawn
    # (registries + SessionSupervisor); `transport: :stdio` only adds the
    # stdio listener on top.
    stdio? = Application.get_env(:docmost_mcp, :start_stdio, true)
    server_child = {DocmostMCP.Server, if(stdio?, do: [transport: :stdio], else: [])}

    # HTTP edge (fork integration): serves /mcp over streamable HTTP with
    # session-identity auth, for the {site}/mcp proxy route.
    http =
      if DocmostMCP.Config.start_http?() do
        [
          {Bandit,
           plug: {DocmostMCP.HTTP, []}, scheme: :http, port: DocmostMCP.Config.http_port()}
        ]
      else
        []
      end

    children = [DocmostMCP.VersionStore | http] ++ [server_child]

    Supervisor.start_link(children, strategy: :one_for_one, name: DocmostMCP.Supervisor)
  end
end
