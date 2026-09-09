defmodule DocmostMCP.SessionJWT do
  @moduledoc "Test helper: mints docmost-style HS256 session JWTs."
  import ExUnit.Assertions

  @secret "test-app-secret"

  def secret, do: @secret

  def sign(payload, secret \\ @secret) do
    jwk = JOSE.JWK.from_oct(secret)

    {_, token} =
      JOSE.JWT.sign(jwk, %{"alg" => "HS256"}, payload)
      |> JOSE.JWS.compact()

    token
  end

  def session_claims(overrides \\ %{}) do
    Map.merge(
      %{
        "sub" => "11111111-1111-1111-1111-111111111111",
        "email" => "user@example.com",
        "workspaceId" => "22222222-2222-2222-2222-222222222222",
        "type" => "access",
        "exp" => System.os_time(:second) + 3600
      },
      overrides
    )
  end

  def session_token(overrides \\ %{}, secret \\ @secret) do
    sign(session_claims(overrides), secret)
  end

  def assert_config(secret \\ @secret) do
    Application.put_env(:docmost_mcp, :app_secret, secret)
  end

  def expired do
    assert System.os_time(:second) > 0
    System.os_time(:second) - 1
  end
end
