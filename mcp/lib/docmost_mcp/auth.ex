defmodule DocmostMCP.Auth do
  @moduledoc """
  Session-identity authentication for the fork's `{site}/mcp` mount.

  Docmost sessions are HS256 JWTs (`{sub, email, workspaceId, type: "access"}`)
  signed with docmost's `APP_SECRET` and delivered in the `authToken` cookie or
  an `Authorization: Bearer` header. This module verifies those tokens locally
  (signature + expiry — no introspection hop) and exposes the verified identity
  so `DocmostMCP.Client.Req` can forward the same JWT as a Bearer token to the
  Docmost REST API, which accepts it via passport-jwt (cookie OR header).

  Flow per MCP request over streamable HTTP:

    1. `DocmostMCP.Auth.SessionPlug` verifies the credential and puts the claims
       (including the raw token under `"token"`) into `conn.assigns[:mcp_auth_claims]`.
    2. `Noizu.MCP.Transport.StreamableHTTP.Plug` forwards those claims to the
       session per request via `Session.deliver/3`.
    3. The server's `principal:` opt (`principal_from_claims/2`) resolves them in
       the session process immediately before handler dispatch, stashing the
       raw token in the process dictionary (`put_bearer/1`).
    4. `current_bearer/0` — called inside the handler process by the Req client —
       returns that token, so every downstream REST call runs as the signed-in
       user. Static `DOCMOST_API_KEY` remains a fallback for stdio/CLI use.

  The process-dictionary hop is scoped tightly: `principal_from_claims/2` runs
  per request in the session process, and every request that reaches a session
  has already passed `SessionPlug`, so claims (fresh or static-identity) are
  always re-resolved before any handler runs.
  """

  alias DocmostMCP.Config
  alias Noizu.MCP.Auth.Principal

  @bearer_key :docmost_mcp_bearer
  @session_type "access"

  # ── session JWT verification ──────────────────────────────────────────────

  @doc """
  Verify a docmost session JWT (HS256, `APP_SECRET`) and return its claims.

  Only interactive user-session tokens (`type: "access"`) are accepted —
  `api_key`, `collab`, `oauth_access`, and other docmost token types are
  rejected here.

  Returns `{:ok, claims}` or `{:error, :expired | :invalid | :unconfigured}`.
  """
  @spec verify_session_token(String.t()) ::
          {:ok, map()} | {:error, :expired | :invalid | :unconfigured}
  def verify_session_token(token) when is_binary(token) do
    case Config.app_secret() do
      secret when is_binary(secret) and secret != "" -> verify(token, secret)
      _ -> {:error, :unconfigured}
    end
  end

  def verify_session_token(_), do: {:error, :invalid}

  defp verify(token, secret) do
    jwk = JOSE.JWK.from_oct(secret)

    # verify_strict(key, allow, signed): HS256 only — no alg-confusion.
    case JOSE.JWT.verify_strict(jwk, ["HS256"], token) do
      {true, %JOSE.JWT{fields: fields}, _jws} -> check_claims(fields)
      _ -> {:error, :invalid}
    end
  rescue
    _ -> {:error, :invalid}
  end

  defp check_claims(fields) do
    with :ok <- check_expiry(fields),
         :ok <- check_type(fields),
         :ok <- check_subject(fields) do
      {:ok, fields}
    end
  end

  defp check_expiry(%{"exp" => exp}) when is_integer(exp) do
    if exp < System.os_time(:second), do: {:error, :expired}, else: :ok
  end

  defp check_expiry(_), do: :ok

  defp check_type(%{"type" => @session_type}), do: :ok
  defp check_type(_), do: {:error, :invalid}

  defp check_subject(%{"sub" => sub, "workspaceId" => ws})
       when is_binary(sub) and sub != "" and is_binary(ws) and ws != "",
       do: :ok

  defp check_subject(_), do: {:error, :invalid}

  # ── per-request bearer plumbing (see moduledoc step 3/4) ──────────────────

  @doc """
  Server `principal:` opt — resolved per request in the session process right
  before handler dispatch. Records the raw session JWT for the client via
  `put_bearer/1` and returns the typed principal.
  """
  def principal_from_claims(claims, _args) when is_map(claims) do
    put_bearer(claims["token"])

    %Principal{
      subject: {:docmost_user, claims["sub"], claims["workspaceId"]},
      authenticator: :docmost_session,
      claims: claims
    }
  end

  @doc "Record the bearer for the current handler process (nil clears)."
  def put_bearer(token) when is_binary(token) and token != "",
    do: Process.put(@bearer_key, token)

  def put_bearer(_), do: Process.delete(@bearer_key)

  @doc """
  The session JWT recorded for the current handler process, or nil when no
  session identity is in play (stdio/CLI callers fall back to the static key).
  """
  def current_bearer, do: Process.get(@bearer_key)

  @doc "Identity claims as recorded by `SessionPlug` (session or static)."
  def static_claims do
    %{"sub" => "docmost-api-key", "type" => "static"}
  end
end
