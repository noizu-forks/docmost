defmodule DocmostMCP.ToolsCoreTest do
  use ExUnit.Case, async: false

  alias DocmostMCP.TestClient
  alias DocmostMCP.Tools.Core
  alias Noizu.MCP.Ctx

  setup do
    {:ok, _} = TestClient.start()
    %{ctx: %Ctx{}}
  end

  test "spaces_list and pages_list read the data envelope", %{ctx: ctx} do
    assert {:ok, %{spaces: [%{"slug" => "engineering"}]}} = Core.spaces_list(%{}, ctx)
    assert {:ok, %{pages: [%{"id" => "p1"}]}} = Core.pages_list(%{space_id: "s1"}, ctx)
  end

  test "page_get returns the page or the raw client error", %{ctx: ctx} do
    assert {:ok, %{"id" => "p1"}} = Core.page_get(%{page_id: "p1"}, ctx)

    assert {:error, %DocmostMCP.Error{status: 404}} =
             Core.page_get(%{page_id: "missing"}, ctx)
  end

  test "write tool errors format the Docmost error", %{ctx: ctx} do
    Application.put_env(:docmost_mcp, :client, DocmostMCP.StubClient)

    DocmostMCP.StubClient.put(%{
      update_page: {:error, %DocmostMCP.Error{status: 403, message: "forbidden"}}
    })

    on_exit(fn ->
      Application.put_env(:docmost_mcp, :client, DocmostMCP.TestClient)
      DocmostMCP.StubClient.clear()
    end)

    assert {:error, "Docmost request failed (403): forbidden"} =
             Core.page_update(%{page_id: "p1", content: "x", title: nil}, ctx)
  end

  test "write tools are gated on DOCMOST_MCP_WRITES", %{ctx: ctx} do
    Application.put_env(:docmost_mcp, :writes, false)

    on_exit(fn -> Application.put_env(:docmost_mcp, :writes, true) end)

    assert {:error, "writes disabled; set DOCMOST_MCP_WRITES=1"} =
             Core.page_create(%{space_id: "s1", title: "T", content: "C"}, ctx)

    assert {:error, "writes disabled; set DOCMOST_MCP_WRITES=1"} =
             Core.page_delete(%{confirm: true, page_id: "p1"}, ctx)

    assert {:error, "writes disabled; set DOCMOST_MCP_WRITES=1"} =
             Core.page_share(
               %{page_id: "p1", share: :public, include_sub_pages: false, search_indexing: false},
               ctx
             )
  end

  test "page create, update, and delete with confirm", %{ctx: ctx} do
    assert {:ok, %{"id" => "p-new", "title" => "Created"}} =
             Core.page_create(
               %{space_id: "s1", title: "Created", content: "Hi", parent_page_id: nil},
               ctx
             )

    assert {:ok, page} =
             Core.page_update(
               %{page_id: "p1", content: "New body", title: "Renamed"},
               ctx
             )

    assert page["title"] == "Renamed"

    assert {:ok, %{ok: true}} =
             Core.page_delete(%{confirm: true, page_id: "p-new"}, ctx)
  end

  test "page delete without confirm is refused", %{ctx: ctx} do
    assert {:error, "confirm=true is required"} = Core.page_delete(%{page_id: "p1"}, ctx)
  end

  test "page_share returns canonical yaml with the public url", %{ctx: ctx} do
    args = %{page_id: "p1", share: :public, include_sub_pages: true, search_indexing: false}
    assert {:ok, yaml} = Core.page_share(args, ctx)
    assert yaml =~ "share: \"public\""
    assert yaml =~ "https://docs.example.com/share/public-key/p/untitled-start"
  end

  test "page_share maps inherited-share errors", %{ctx: ctx} do
    TestClient.put_share("p1", %{"shared" => true, "id" => "anc", "key" => "k", "level" => 1})

    args = %{page_id: "p1", share: :public, include_sub_pages: false, search_indexing: false}

    assert {:error, "operation would remove inherited access; change the ancestor instead"} =
             Core.page_share(args, ctx)
  end

  test "generic errors normalize to a plain message", %{ctx: ctx} do
    Application.put_env(:docmost_mcp, :client, DocmostMCP.StubClient)
    DocmostMCP.StubClient.put(%{delete_page: {:error, :eio}})

    on_exit(fn ->
      Application.put_env(:docmost_mcp, :client, DocmostMCP.TestClient)
      DocmostMCP.StubClient.clear()
    end)

    assert {:error, "Docmost request failed"} =
             Core.page_delete(%{confirm: true, page_id: "p1"}, ctx)
  end
end
