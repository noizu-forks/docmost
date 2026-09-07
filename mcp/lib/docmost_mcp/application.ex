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

    children = [DocmostMCP.VersionStore | transport]

    Supervisor.start_link(children, strategy: :one_for_one, name: DocmostMCP.Supervisor)
  end
end
