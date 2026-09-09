defmodule DocmostMCP.ClientTest do
  use ExUnit.Case, async: false

  # Delegation smoke tests: every DocmostMCP.Client function forwards to the
  # configured client module (TestClient here).
  setup do
    {:ok, _} = DocmostMCP.TestClient.start()
    Application.put_env(:docmost_mcp, :client, DocmostMCP.TestClient)
    :ok
  end

  test "explicit-arity readers delegate with default cursor" do
    assert {:ok, %{"data" => [_space]}} = DocmostMCP.Client.list_spaces()
    assert {:ok, %{"data" => [_page]}} = DocmostMCP.Client.list_pages("s1")
    assert {:ok, %{"data" => []}} = DocmostMCP.Client.list_child_pages("p1")
    assert {:ok, %{"restriction" => "none"}} = DocmostMCP.Client.get_access("p1")
  end

  test "generated delegates forward to the client" do
    assert {:ok, %{"id" => "s1"}} = DocmostMCP.Client.get_space("s1")
    assert {:ok, %{"id" => "s-new"}} = DocmostMCP.Client.create_space(%{name: "N"})
    assert {:ok, %{"id" => "p1"}} = DocmostMCP.Client.get_page("p1")
    assert {:ok, %{"id" => "p-new"}} = DocmostMCP.Client.create_page(%{spaceId: "s1", title: "T"})
    assert {:ok, page} = DocmostMCP.Client.update_page("p1", %{title: "New"})
    assert page["title"] == "New"
    assert :ok = DocmostMCP.Client.delete_page("p-new")
    assert {:ok, share} = DocmostMCP.Client.get_share("p1")
    assert share["shared"] == false
    assert {:ok, _} = DocmostMCP.Client.update_share("p1", %{shared: true})
    assert {:ok, _} = DocmostMCP.Client.set_restriction("p1", true)
    assert {:ok, _} = DocmostMCP.Client.add_grants("p1", [])
    assert {:ok, _} = DocmostMCP.Client.update_grant("p1", "g-1", "writer")
    assert {:ok, _} = DocmostMCP.Client.remove_grant("p1", "g-1")
  end

  test "errors flow through unchanged" do
    assert {:error, %DocmostMCP.Error{status: 404}} = DocmostMCP.Client.get_page("missing")
  end
end
