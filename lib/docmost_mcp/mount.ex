defmodule DocmostMCP.Mount do
  @moduledoc """
  Local-filesystem mount transport wiring (opt-in via `DOCMOST_MCP_MOUNT_TOKEN`).

  Hosts a `Noizu.MCP.Transport.VFSWS` WebSocket endpoint with Bandit so
  `mcp-mount` can project the wiki as a filesystem. Notes for operators:

    * `VFSWS` self-routes `GET /vfs` on its own dedicated port — it is never
      Phoenix-forwarded and never shares the MCP server's transport ports.
    * The mount token is SEPARATE from `DOCMOST_API_KEY`: it authorizes the
      WebSocket only and grants no Docmost HTTP credentials.
    * Auth is two-layer: the HTTP upgrade requires a valid
      `Authorization: Bearer <token>` (401 before any socket exists), and the
      first WebSocket frame must be `vfs/auth` with the same token — a wrong
      frame token draws a `-32001` error and the connection closes.
    * The listener binds to 127.0.0.1 only.
  """

  def enabled?, do: not is_nil(token())

  def token, do: Application.get_env(:docmost_mcp, :mount_token)

  def port, do: Application.get_env(:docmost_mcp, :mount_port, 4700)

  @doc "Plug options for `Noizu.MCP.Transport.VFSWS`."
  def ws_plug_opts do
    [
      server: DocmostMCP.Server,
      auth: [
        verifier:
          {Noizu.MCP.Auth.ApiKeyVerifier,
           keys: [{token(), %{"sub" => "docmost-mount", "scope" => "vfs"}}],
           default_claims: %{"scope" => "vfs"}}
      ]
    ]
  end

  @doc "Supervisor children for the mount stack (empty when disabled)."
  def children do
    if enabled?() do
      [
        {Noizu.MCP.Server.VFSPubSub, []},
        {Bandit,
         plug: {Noizu.MCP.Transport.VFSWS, ws_plug_opts()},
         scheme: :http,
         port: port(),
         ip: {127, 0, 0, 1}}
      ]
    else
      []
    end
  end
end
