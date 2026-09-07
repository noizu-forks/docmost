defmodule DocmostMCP.Auth.SessionPlugTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias DocmostMCP.Auth.SessionPlug
  alias DocmostMCP.SessionJWT

  @opts SessionPlug.init([])

  setup do
    SessionJWT.assert_config()
    Application.put_env(:docmost_mcp, :allow_static_key, false)
    Application.put_env(:docmost_mcp, :api_key, "static-shared-key")

    on_exit(fn ->
      Application.delete_env(:docmost_mcp, :app_secret)
      Application.delete_env(:docmost_mcp, :allow_static_key)
      Application.put_env(:docmost_mcp, :api_key, "test-token")
    end)

    :ok
  end

  defp call_plug(conn), do: SessionPlug.call(conn, @opts)

  defp conn_with_cookie(cookie) do
    conn(:post, "/mcp", nil)
    |> put_req_header("cookie", "authToken=" <> cookie)
  end

  defp conn_with_bearer(token) do
    conn(:post, "/mcp", nil)
    |> put_req_header("authorization", "Bearer " <> token)
  end

  describe "session identity" do
    test "valid authToken cookie is verified and claims assigned" do
      conn = SessionJWT.session_token() |> conn_with_cookie() |> call_plug()

      refute conn.halted
      claims = conn.assigns[:mcp_auth_claims]
      assert claims["sub"] == "11111111-1111-1111-1111-111111111111"
      assert claims["token"] == SessionJWT.session_token()
    end

    test "valid Authorization Bearer session token is verified" do
      token = SessionJWT.session_token()
      conn = token |> conn_with_bearer() |> call_plug()

      refute conn.halted
      assert conn.assigns[:mcp_auth_claims]["token"] == token
    end

    test "expired session token is a 401 JSON-RPC error" do
      token = SessionJWT.session_token(%{"exp" => SessionJWT.expired()})
      conn = token |> conn_with_cookie() |> call_plug()

      assert conn.halted
      assert conn.status == 401

      assert %{"error" => %{"code" => -32001, "message" => "session token expired"}} =
               Jason.decode!(conn.resp_body)
    end

    test "tampered token is a 401" do
      token = SessionJWT.session_token() <> "x"
      conn = token |> conn_with_bearer() |> call_plug()

      assert conn.halted
      assert conn.status == 401
    end

    test "api_key-type bearer token is rejected (no session identity)" do
      token = SessionJWT.session_token(%{"type" => "api_key"})
      conn = token |> conn_with_bearer() |> call_plug()

      assert conn.halted
      assert conn.status == 401
    end

    test "unconfigured server secret is a clean 401" do
      Application.delete_env(:docmost_mcp, :app_secret)
      conn = SessionJWT.session_token() |> conn_with_cookie() |> call_plug()

      assert conn.halted
      assert conn.status == 401

      assert %{"error" => %{"message" => "server is missing DOCMOST_APP_SECRET"}} =
               Jason.decode!(conn.resp_body)
    end
  end

  describe "static shared-key fallback" do
    test "disabled by default: no credential is a 401" do
      conn = call_plug(conn(:post, "/mcp", nil))

      assert conn.halted
      assert conn.status == 401

      assert %{"error" => %{"message" => "authentication required"}} =
               Jason.decode!(conn.resp_body)
    end

    test "enabled and matching key passes with static identity claims" do
      Application.put_env(:docmost_mcp, :allow_static_key, true)
      conn = "static-shared-key" |> conn_with_bearer() |> call_plug()

      refute conn.halted
      assert conn.assigns[:mcp_auth_claims] == %{"sub" => "docmost-api-key", "type" => "static"}
    end

    test "enabled but wrong key is a 401" do
      Application.put_env(:docmost_mcp, :allow_static_key, true)
      conn = "wrong-key" |> conn_with_bearer() |> call_plug()

      assert conn.halted
      assert conn.status == 401
    end

    test "enabled but no credential is a 401" do
      Application.put_env(:docmost_mcp, :allow_static_key, true)
      conn = call_plug(conn(:post, "/mcp", nil))

      assert conn.halted
      assert conn.status == 401
    end

    test "invalid session cookie never falls back to the static key" do
      Application.put_env(:docmost_mcp, :allow_static_key, true)
      token = SessionJWT.session_token(%{"exp" => SessionJWT.expired()})
      conn = token |> conn_with_cookie() |> call_plug()

      assert conn.halted
      assert conn.status == 401
    end
  end
end
