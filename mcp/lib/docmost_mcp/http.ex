defmodule DocmostMCP.HTTP do
  @moduledoc """
  HTTP edge for the MCP service, served by Bandit on `DOCMOST_MCP_HTTP_PORT`
  (default 4000):

      /mcp   → MCP streamable HTTP (`Noizu.MCP.Transport.StreamableHTTP.Plug`),
               gated by `DocmostMCP.Auth.SessionPlug`
      else   → 404

  The edge proxy (mcp/Caddyfile) routes `{site}/mcp*` here without rewriting
  the path, so the streamable transport is mounted at exactly `/mcp` as MCP
  clients expect. This module is written as a plain `@behaviour Plug` rather
  than `Plug.Router` so its options resolve at runtime (env-driven config in
  a release) instead of at compile time.
  """

  @behaviour Plug
  import Plug.Conn

  alias DocmostMCP.Auth.SessionPlug
  alias Noizu.MCP.Transport.StreamableHTTP

  @impl Plug
  def init(opts) do
    %{
      session_plug: SessionPlug.init(opts),
      # `origins: :any` is safe here: every request has already passed the
      # session plug, so origin spoofing buys an attacker nothing. Pass an
      # allowlist via `origins:` opt to tighten for browser-MCP clients.
      streamable:
        StreamableHTTP.Plug.init(
          server: DocmostMCP.Server,
          origins: Keyword.get(opts, :origins, :any)
        )
    }
  end

  @impl Plug
  def call(%{path_info: ["mcp" | rest]} = conn, cfg) do
    conn = %{conn | path_info: rest, script_name: conn.script_name ++ ["mcp"]}

    conn = SessionPlug.call(conn, cfg.session_plug)

    if conn.halted do
      conn
    else
      StreamableHTTP.Plug.call(conn, cfg.streamable)
    end
  end

  def call(conn, _cfg) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "not found; MCP is served at /mcp"}))
  end
end
