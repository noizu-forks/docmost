defmodule DocmostMCP.HTTPTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias DocmostMCP.HTTP
  alias DocmostMCP.SessionJWT

  # `origins: :any` default; the session plug is the authentication gate.
  @opts HTTP.init(origins: :any)

  setup do
    SessionJWT.assert_config()

    on_exit(fn -> Application.delete_env(:docmost_mcp, :app_secret) end)
    :ok
  end

  test "requests outside /mcp get a 404" do
    conn = HTTP.call(conn(:get, "/", nil), @opts)

    assert conn.status == 404
  end

  test "unauthenticated /mcp requests are 401 before reaching the transport" do
    conn = HTTP.call(conn(:post, "/mcp", nil), @opts)

    assert conn.status == 401
  end

  test "a valid session cookie passes the auth gate into the transport" do
    conn =
      conn(:post, "/mcp", nil)
      |> put_req_header("cookie", "authToken=" <> SessionJWT.session_token())
      |> put_req_header("content-type", "application/json")
      |> put_private(:abs_path, "/mcp")
      |> then(&%{&1 | path_info: ["mcp"]})
      |> HTTP.call(@opts)

    # Past SessionPlug; the streamable transport now owns the response. A body
    # without auth failure proves the handoff — exact MCP semantics are the
    # transport's contract, covered by noizu_mcp's own suite.
    refute conn.status == 401
  end
end
