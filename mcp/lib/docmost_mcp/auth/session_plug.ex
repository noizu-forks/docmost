defmodule DocmostMCP.Auth.SessionPlug do
  @moduledoc """
  Plug run ahead of `Noizu.MCP.Transport.StreamableHTTP.Plug` on the HTTP
  mount. Resolves the caller's identity:

    1. docmost session JWT — `authToken` cookie (forwarded by the edge proxy)
       or `Authorization: Bearer` — verified locally against `DOCMOST_APP_SECRET`;
    2. static shared key — `Authorization: Bearer <DOCMOST_API_KEY>`, only when
       `DOCMOST_MCP_ALLOW_STATIC_KEY=1` and no session token was presented
       (local/dev CLI use).

  On success the verified claims land in `conn.assigns[:mcp_auth_claims]`,
  which the streamable transport forwards to the MCP session per request. On
  failure the request is answered with `401` and a JSON-RPC error body — MCP
  clients surface that cleanly.
  """

  @behaviour Plug
  import Plug.Conn

  alias DocmostMCP.{Auth, Config}

  @unauthorized_code -32001

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case authenticate(conn) do
      {:ok, claims} ->
        assign(conn, :mcp_auth_claims, claims)

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(unauthorized_body(reason)))
        |> halt()
    end
  end

  defp authenticate(conn) do
    case fetch_token(conn) do
      {:ok, token, :cookie} ->
        # A session cookie that fails verification must not silently fall back
        # to the static key — the browser asked to act as its signed-in user.
        case Auth.verify_session_token(token) do
          {:ok, claims} -> {:ok, Map.put(claims, "token", token)}
          {:error, reason} -> {:error, reason}
        end

      {:ok, token, :bearer} ->
        # CLI/programmatic callers may present the session JWT as Bearer; the
        # static shared key is accepted on the same header, but only when
        # opted in — an invalid credential is never downgraded.
        case Auth.verify_session_token(token) do
          {:ok, claims} ->
            {:ok, Map.put(claims, "token", token)}

          {:error, reason} ->
            if static_match?(token) do
              {:ok, Auth.static_claims()}
            else
              {:error, reason}
            end
        end

      :none ->
        {:error, :missing}
    end
  end

  defp static_match?(token) do
    Config.allow_static_key?() and Config.static_api_key() == token
  end

  defp fetch_token(conn) do
    with_cookie(conn) || with_bearer(conn) || :none
  end

  defp with_cookie(conn) do
    case conn |> get_req_header("cookie") |> List.first() do
      header when is_binary(header) ->
        case Plug.Conn.Cookies.decode(header)["authToken"] do
          token when is_binary(token) and token != "" -> {:ok, token, :cookie}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp with_bearer(conn) do
    case bearer_token(conn) do
      token when is_binary(token) and token != "" -> {:ok, token, :bearer}
      _ -> nil
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> String.trim(token)
      ["bearer " <> token | _] -> String.trim(token)
      _ -> nil
    end
  end

  defp unauthorized_body(reason) do
    message =
      case reason do
        :expired -> "session token expired"
        :invalid -> "invalid session token"
        :unconfigured -> "server is missing DOCMOST_APP_SECRET"
        :missing -> "authentication required"
        _ -> "unauthorized"
      end

    %{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{"code" => @unauthorized_code, "message" => message}
    }
  end
end
