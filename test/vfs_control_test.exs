defmodule DocmostMCP.VFSControlTest do
  use ExUnit.Case, async: false

  alias DocmostMCP.VFS.Controlled
  alias Noizu.MCP.Ctx

  setup do
    {:ok, _} = DocmostMCP.TestClient.start()
    DocmostMCP.VersionStore.reset()

    original = Application.get_env(:docmost_mcp, :writes)
    on_exit(fn -> Application.put_env(:docmost_mcp, :writes, original) end)

    %{ctx: %Ctx{}}
  end

  test "the composed backend implements the mutating VFS surface" do
    implemented = Controlled.__mcp_vfs__(:implemented)

    for op <- [:stat, :list, :read, :write, :create, :remove, :search, :xattr] do
      assert op in implemented, "expected #{inspect(op)} in #{inspect(implemented)}"
    end
  end

  test "non-control paths delegate to the real backend", %{ctx: ctx} do
    assert {:ok, content, _} = Controlled.read("/engineering/start.md", ctx)
    assert content =~ "# Start"
    assert {:ok, entries, nil} = Controlled.list("/engineering", nil, ctx)
    assert Enum.any?(entries, &match?(%{name: "start.md"}, &1))
  end

  test "the root listing merges the etc/dev control branch", %{ctx: ctx} do
    assert {:ok, entries, nil} = Controlled.list("/", nil, ctx)
    assert Enum.any?(entries, &match?(%{name: "etc", type: :dir}, &1))
    assert Enum.any?(entries, &match?(%{name: "engineering", type: :dir}, &1))

    assert {:ok, dev, nil} = Controlled.list("/etc/dev", nil, ctx)
    assert Enum.map(dev, & &1.name) == ["cache", "config", "runtime", "tools"]

    assert {:ok, config, nil} = Controlled.list("/etc/dev/config", nil, ctx)
    names = Enum.map(config, & &1.name)
    assert "writes" in names
    assert "trace" in names
    assert "cache_enabled" in names
  end

  test "the writes toggle reads and writes through Config", %{ctx: ctx} do
    assert {:ok, node} = Controlled.stat("/etc/dev/config/writes", ctx)
    assert node.type == :control and node.writable == true

    assert {:ok, current, _} = Controlled.read("/etc/dev/config/writes", ctx)
    assert current == Jason.encode!(DocmostMCP.Config.writes?())

    assert {:ok, _} = Controlled.write("/etc/dev/config/writes", "false", ctx)
    refute DocmostMCP.Config.writes?()

    assert {:ok, _} = Controlled.write("/etc/dev/config/writes", "true", ctx)
    assert DocmostMCP.Config.writes?()
  end

  test "invalid toggle payloads are :eio and never raise", %{ctx: ctx} do
    assert {:error, :eio} = Controlled.write("/etc/dev/config/writes", "not-json", ctx)
    assert {:error, :eio} = Controlled.write("/etc/dev/config/writes", "\"yes\"", ctx)
  end

  test "unknown control paths are :enoent", %{ctx: ctx} do
    assert {:error, :enoent} = Controlled.stat("/etc/dev/config/nope", ctx)
    assert {:error, :enoent} = Controlled.read("/etc/dev/config/nope", ctx)
    assert {:error, :enoent} = Controlled.write("/etc/dev/config/nope", "x", ctx)
  end

  test "writes off gates mutating ops through the composed backend", %{ctx: ctx} do
    assert {:ok, _} = Controlled.write("/etc/dev/config/writes", "false", ctx)

    assert {:error, :eacces} = Controlled.write("/engineering/start.md", "x", ctx)
    assert {:error, :eacces} = Controlled.create("/engineering/new.md", "x", ctx)
    assert {:error, :eacces} = Controlled.remove("/engineering/start.md", ctx)
    assert {:ok, node} = Controlled.stat("/engineering/start.md", ctx)
    assert node.writable == false
  end

  test "writes on restores mutating ops and writable flags", %{ctx: ctx} do
    assert {:ok, _} = Controlled.write("/etc/dev/config/writes", "true", ctx)

    assert {:ok, node} = Controlled.write("/engineering/start.md", "# Toggled\n", ctx)
    assert node.version > 0
    assert {:ok, stat} = Controlled.stat("/engineering/start.md", ctx)
    assert stat.writable == true
  end

  test "the cache flush control node accepts writes", %{ctx: ctx} do
    assert {:ok, node} = Controlled.write("/etc/dev/cache/flush", "{}", ctx)
    assert node.xattrs["response"] == "ok"
    assert {:ok, _, _} = Controlled.read("/etc/dev/cache/flush", ctx)
  end

  test "set_writes! never raises on invalid payloads" do
    assert DocmostMCP.Config.set_writes!(true) == :ok
    assert DocmostMCP.Config.set_writes!(false) == :ok
    assert {:error, :einval} = DocmostMCP.Config.set_writes!("yes")
    assert {:error, :einval} = DocmostMCP.Config.set_writes!(nil)
  end
end
