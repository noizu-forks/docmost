defmodule DocmostMCP.VersionStoreTest do
  use ExUnit.Case, async: false

  setup do
    DocmostMCP.VersionStore.reset()
    on_exit(fn -> DocmostMCP.VersionStore.reset() end)
    :ok
  end

  test "fresh paths start at the boot epoch, never at the legacy constant 1" do
    version = GenServer.call(DocmostMCP.VersionStore, {:version, "fresh-path", "fp1"})
    # The boot epoch is a wall-clock second — far above the legacy floor of 1.
    assert version > 1
  end

  test "same fingerprint keeps the version stable" do
    v1 = version_of("p", "f")
    v2 = version_of("p", "f")
    assert v1 == v2
  end

  test "a changed fingerprint bumps by exactly one" do
    v1 = version_of("p", "f1")
    v2 = version_of("p", "f2")
    assert v2 == v1 + 1
  end

  test "A -> B -> A is strictly increasing throughout" do
    a1 = version_of("p", "a")
    b1 = version_of("p", "b")
    a2 = version_of("p", "a")
    b2 = version_of("p", "b")

    assert a1 < b1
    assert b1 < a2
    assert a2 < b2
  end

  test "reset makes every subsequent version strictly greater than any pre-reset version" do
    v1 = version_of("p", "f")
    v2 = version_of("q", "g")
    highest = max(v1, v2)

    assert :ok = DocmostMCP.VersionStore.reset()

    assert version_of("p", "f") > highest
    assert version_of("brand-new", "h") > highest
  end

  defp version_of(path, fingerprint) do
    GenServer.call(DocmostMCP.VersionStore, {:version, path, fingerprint})
  end
end
