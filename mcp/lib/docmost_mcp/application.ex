defmodule DocmostMCP.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    transport =
      if Application.get_env(:docmost_mcp, :start_stdio, true) do
        [{DocmostMCP.Server, transport: :stdio}]
      else
        []
      end

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

    children = [DocmostMCP.VersionStore | http] ++ transport

    Supervisor.start_link(children, strategy: :one_for_one, name: DocmostMCP.Supervisor)
  end
end
