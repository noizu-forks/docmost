defmodule DocmostMCP.MountTest do
  use ExUnit.Case, async: false

  setup do
    token = Application.get_env(:docmost_mcp, :mount_token)
    port = Application.get_env(:docmost_mcp, :mount_port)

    on_exit(fn ->
      Application.put_env(:docmost_mcp, :mount_token, token)
      Application.put_env(:docmost_mcp, :mount_port, port)
    end)

    :ok
  end

  test "disabled without a token: no children, no listener" do
    Application.delete_env(:docmost_mcp, :mount_token)
    refute DocmostMCP.Mount.enabled?()
    assert DocmostMCP.Mount.children() == []
  end

  test "enabled with a token: pubsub plus a localhost-only Bandit listener" do
    Application.put_env(:docmost_mcp, :mount_token, "secret-mount-token")
    Application.put_env(:docmost_mcp, :mount_port, 4_799)

    assert DocmostMCP.Mount.enabled?()

    assert [{Noizu.MCP.Server.VFSPubSub, []}, {Bandit, opts}] = DocmostMCP.Mount.children()
    assert opts[:port] == 4_799
    assert opts[:ip] == {127, 0, 0, 1}
    assert {Noizu.MCP.Transport.VFSWS, plug_opts} = opts[:plug]
    assert plug_opts[:server] == DocmostMCP.Server
  end

  test "ws_plug_opts binds the mount token to ApiKeyVerifier with vfs scope claims" do
    Application.put_env(:docmost_mcp, :mount_token, "secret-mount-token")

    assert [server: DocmostMCP.Server, auth: auth] = DocmostMCP.Mount.ws_plug_opts()

    assert [{verifier, verifier_opts}] = Keyword.get_values(auth, :verifier)
    assert verifier == Noizu.MCP.Auth.ApiKeyVerifier

    assert {keys, default_claims} = {verifier_opts[:keys], verifier_opts[:default_claims]}
    assert [{"secret-mount-token", claims}] = keys
    assert claims["sub"] == "docmost-mount"
    assert claims["scope"] == "vfs"
    assert default_claims == %{"scope" => "vfs"}
  end
end
