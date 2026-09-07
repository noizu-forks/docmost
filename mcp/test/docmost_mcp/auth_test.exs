defmodule DocmostMCP.AuthTest do
  use ExUnit.Case, async: false

  alias DocmostMCP.{Auth, SessionJWT}

  setup do
    SessionJWT.assert_config()

    on_exit(fn -> Application.delete_env(:docmost_mcp, :app_secret) end)
    :ok
  end

  describe "verify_session_token/1" do
    test "accepts a valid user-session token" do
      {:ok, claims} = Auth.verify_session_token(SessionJWT.session_token())
      assert claims["type"] == "access"
      assert claims["workspaceId"] == "22222222-2222-2222-2222-222222222222"
    end

    test "rejects an expired token" do
      token = SessionJWT.session_token(%{"exp" => SessionJWT.expired()})
      assert {:error, :expired} = Auth.verify_session_token(token)
    end

    test "rejects a token signed with a different secret" do
      token = SessionJWT.session_token(%{}, "other-secret")
      assert {:error, :invalid} = Auth.verify_session_token(token)
    end

    test "rejects a tampered payload (signature mismatch)" do
      [header, payload, signature] = String.split(SessionJWT.session_token(), ".")

      # Corrupt the payload segment deterministically; signature no longer matches.
      last = String.last(payload)
      flipped = if last == "A", do: "B", else: "A"
      tampered = Enum.join([header, String.slice(payload, 0..-2//1) <> flipped, signature], ".")

      assert {:error, :invalid} = Auth.verify_session_token(tampered)
    end

    test "rejects non-access token types (api_key, collab, oauth_access)" do
      for type <- ["api_key", "collab", "oauth_access"] do
        token = SessionJWT.session_token(%{"type" => type})
        assert {:error, :invalid} = Auth.verify_session_token(token)
      end
    end

    test "rejects tokens missing sub or workspaceId" do
      assert {:error, :invalid} =
               Auth.verify_session_token(SessionJWT.session_token(%{"sub" => nil}))

      assert {:error, :invalid} =
               Auth.verify_session_token(SessionJWT.session_token(%{"workspaceId" => ""}))
    end

    test "rejects garbage input" do
      assert {:error, :invalid} = Auth.verify_session_token("not-a-jwt")
      assert {:error, :invalid} = Auth.verify_session_token(42)
    end

    test "reports unconfigured when DOCMOST_APP_SECRET is absent" do
      Application.delete_env(:docmost_mcp, :app_secret)
      assert {:error, :unconfigured} = Auth.verify_session_token(SessionJWT.session_token())
    end
  end

  describe "principal_from_claims/2" do
    test "records the bearer for the current process and builds a principal" do
      claims =
        SessionJWT.session_claims()
        |> Map.put("token", "raw.jwt.token")

      principal = Auth.principal_from_claims(claims, [])

      assert principal.subject == {:docmost_user, claims["sub"], claims["workspaceId"]}
      assert principal.authenticator == :docmost_session
      assert Auth.current_bearer() == "raw.jwt.token"
    after
      Auth.put_bearer(nil)
    end

    test "clears the bearer when claims carry no token" do
      Auth.put_bearer("stale")
      Auth.principal_from_claims(SessionJWT.session_claims(), [])
      assert Auth.current_bearer() == nil
    end
  end
end
