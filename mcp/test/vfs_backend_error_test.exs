defmodule DocmostMCP.VFSBackendErrorTest do
  use ExUnit.Case, async: false

  alias DocmostMCP.StubClient
  alias DocmostMCP.VFS.Backend
  alias Noizu.MCP.Ctx

  @space %{"id" => "s1", "slug" => "engineering", "name" => "Engineering"}

  setup do
    DocmostMCP.VersionStore.reset()
    Application.put_env(:docmost_mcp, :client, StubClient)
    StubClient.put(%{list_spaces: {:ok, %{"data" => [@space], "meta" => %{}}}})

    on_exit(fn ->
      Application.put_env(:docmost_mcp, :client, DocmostMCP.TestClient)
      StubClient.clear()
    end)

    %{ctx: %Ctx{}}
  end

  defp page(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "p1",
        "slugId" => "start",
        "spaceId" => "s1",
        "title" => "Start",
        "parentPageId" => nil
      },
      overrides
    )
  end

  defp put_pages(pages) do
    StubClient.put(%{
      list_spaces: {:ok, %{"data" => [@space], "meta" => %{}}},
      list_pages: fn [_space, _cursor] ->
        {:ok, %{"data" => Enum.filter(pages, &is_nil(&1["parentPageId"])), "meta" => %{}}}
      end,
      list_child_pages: fn [parent, _cursor] ->
        {:ok, %{"data" => Enum.filter(pages, &(&1["parentPageId"] == parent)), "meta" => %{}}}
      end,
      get_page: fn [id] ->
        case Enum.find(pages, &(&1["id"] == id)) do
          nil -> {:error, %DocmostMCP.Error{status: 404, message: "not found"}}
          page -> {:ok, page}
        end
      end
    })
  end

  test "list surfaces errno-mapped client errors", %{ctx: ctx} do
    StubClient.put(%{list_spaces: StubClient.error(500)})
    assert {:error, :eio} = Backend.list("/", nil, ctx)

    StubClient.put(%{list_spaces: StubClient.error(401)})
    assert {:error, :eio} = Backend.list("/", nil, ctx)

    put_pages([page()])
    StubClient.put(%{list_pages: StubClient.error(403)})
    assert {:error, :eacces} = Backend.list("/engineering", nil, ctx)

    StubClient.put(%{list_pages: StubClient.error(404)})
    assert {:error, :enoent} = Backend.list("/engineering", nil, ctx)

    StubClient.put(%{list_pages: StubClient.error(500)})
    assert {:error, :eio} = Backend.list("/engineering", nil, ctx)
  end

  test "list cursor loops are eio", %{ctx: ctx} do
    StubClient.put(%{
      list_spaces: {:ok, %{"data" => [@space], "meta" => %{"nextCursor" => "c"}}}
    })

    assert {:error, :eio} = Backend.list("/", nil, ctx)

    StubClient.put(%{
      list_spaces: {:ok, %{"data" => [@space], "meta" => %{}}},
      list_pages: {:ok, %{"data" => [page()], "meta" => %{"nextCursor" => "c"}}}
    })

    assert {:error, :eio} = Backend.list("/engineering", nil, ctx)
  end

  test "child pagination and hydration cycle guards", %{ctx: ctx} do
    StubClient.put(%{
      list_pages: {:ok, %{"data" => [page()], "meta" => %{}}},
      list_child_pages: fn ["p1", _] ->
        {:ok, %{"data" => [page(%{"id" => "p1"})], "meta" => %{}}}
      end
    })

    assert {:error, :eio} = Backend.list("/engineering", nil, ctx)

    StubClient.put(%{
      list_pages: {:ok, %{"data" => [page()], "meta" => %{}}},
      list_child_pages:
        {:ok, %{"data" => [page(%{"id" => "c1", "parentPageId" => "p1"})], "meta" => %{}}}
    })

    StubClient.put(%{
      list_child_pages: fn
        ["p1", _] ->
          {:ok, %{"data" => [page(%{"id" => "c1", "parentPageId" => "p1"})], "meta" => %{}}}

        ["c1", _] ->
          {:ok, %{"data" => [page()], "meta" => %{}}}
      end
    })

    assert {:error, :eio} = Backend.list("/engineering", nil, ctx)

    StubClient.put(%{
      list_pages: {:ok, %{"data" => [page()], "meta" => %{}}},
      list_child_pages: fn [_parent, _cursor] ->
        {:ok, %{"data" => [], "meta" => %{"nextCursor" => "dup"}}}
      end
    })

    assert {:error, :eio} = Backend.list("/engineering", nil, ctx)
  end

  test "stat and read error paths", %{ctx: _ctx} do
    put_pages([page()])

    assert {:error, :enoent} = Backend.stat("/nope", %Ctx{})
    assert {:error, :enoent} = Backend.stat("/engineering/missing.md", %Ctx{})
    assert {:error, :eisdir} = Backend.read("/", %Ctx{})
    assert {:error, :eisdir} = Backend.read("/engineering", %Ctx{})
    assert {:error, :eisdir} = Backend.read("/engineering/start", %Ctx{})
    assert {:error, :enoent} = Backend.read("/engineering/missing.md", %Ctx{})
    assert {:error, :enotdir} = Backend.list("/engineering/start.md", nil, %Ctx{})

    StubClient.put(%{get_share: StubClient.error(500)})

    assert {:error, %DocmostMCP.Error{status: 500}} =
             Backend.stat("/engineering/start.meta", %Ctx{})
  end

  test "stat and xattr on page and meta", %{ctx: _ctx} do
    put_pages([page(%{"content" => "# Start\n", "updatedAt" => "2026-01-01T00:00:00Z"})])

    StubClient.put(%{
      get_share: {:ok, %{"shared" => false}},
      get_access: {:ok, %{"restriction" => "none", "grants" => []}}
    })

    assert {:ok, stat} = Backend.stat("/engineering/start.md", %Ctx{})
    assert stat.type == :file

    assert {:ok, %{"kind" => "page", "id" => "p1"}} =
             Backend.xattr("/engineering/start.md", %Ctx{})

    assert {:ok, %{"kind" => "meta"}} = Backend.xattr("/engineering/start.meta", %Ctx{})
    assert {:ok, attrs} = Backend.xattr("/engineering", %Ctx{})
    assert attrs == %{"id" => "s1"}
  end

  test "search across root, space, and page_dir kinds", %{ctx: _ctx} do
    put_pages([page(%{"content" => "needle here\nnope"})])
    assert {:ok, matches, nil} = Backend.search("/", "needle", %Ctx{})
    assert [%{path: "/engineering/start.md", line: 1}] = matches
    assert {:ok, matches, nil} = Backend.search("/engineering", "needle", %Ctx{})
    assert [%{path: "/engineering/start.md"}] = matches

    assert {:ok, matches, nil} = Backend.search("/engineering/start", "needle", %Ctx{})
    assert [%{path: "/engineering/start.md"}] = matches

    assert {:ok, [], nil} = Backend.search("/engineering", "absent-needle", %Ctx{})
    assert {:error, :enoent} = Backend.search("/nope", "x", %Ctx{})
  end

  test "create space succeeds and maps failures", %{ctx: _ctx} do
    StubClient.put(%{create_space: {:ok, %{"id" => "s2"}}})
    assert {:ok, stat} = Backend.create("/design", :dir, %Ctx{})
    assert stat.type == :dir

    StubClient.put(%{create_space: StubClient.error(500)})
    assert {:error, :eio} = Backend.create("/design", :dir, %Ctx{})
  end

  test "create page, duplicates, parents, and failures", %{ctx: _ctx} do
    put_pages([page()])

    StubClient.put(%{
      create_page:
        {:ok, %{"id" => "p2", "slugId" => "fresh", "spaceId" => "s1", "title" => "Fresh"}}
    })

    assert {:ok, stat} = Backend.create("/engineering/fresh.md", "# Fresh\n", %Ctx{})
    assert stat.type == :file

    assert {:error, :eexist} = Backend.create("/engineering/start.md", "dup", %Ctx{})
    assert {:error, :eexist} = Backend.create("/engineering/start.meta", "dup", %Ctx{})
    assert {:error, :enosys} = Backend.create("/", :dir, %Ctx{})
    assert {:error, :enoent} = Backend.create("/engineering/nope/child.md", "x", %Ctx{})

    StubClient.put(%{create_page: StubClient.error(500)})
    assert {:error, :eio} = Backend.create("/engineering/fresh2.md", "# F\n", %Ctx{})
  end

  test "create page under a parent uses the parent id", %{ctx: _ctx} do
    child = page(%{"id" => "c1", "slugId" => "child", "parentPageId" => "p1"})
    put_pages([page(), child])

    StubClient.put(%{
      create_page: fn [attrs] ->
        assert attrs.parentPageId == "p1"
        {:ok, %{"id" => "p3", "slugId" => "under-child", "spaceId" => "s1"}}
      end
    })

    assert {:ok, _} = Backend.create("/engineering/start/leaf.md", "# Leaf\n", %Ctx{})
  end

  test "write page maps client failure to eio and missing to enoent", %{ctx: _ctx} do
    put_pages([page()])

    StubClient.put(%{update_page: StubClient.error(500)})
    assert {:error, :eio} = Backend.write("/engineering/start.md", "# X\n", %Ctx{})

    StubClient.put(%{update_page: StubClient.error(404)})
    assert {:error, :eio} = Backend.write("/engineering/start.md", "# X\n", %Ctx{})

    assert {:error, :enoent} = Backend.write("/engineering/missing.md", "# X\n", %Ctx{})
    assert {:error, :eisdir} = Backend.write("/engineering/start", "x", %Ctx{})
  end

  test "write page with meta header updates title and parent", %{ctx: _ctx} do
    put_pages([page()])

    StubClient.put(%{
      update_page: fn [id, attrs] ->
        assert id == "p1"
        assert attrs.title == "Renamed"
        assert attrs.parentPageId == "root"
        {:ok, Map.merge(page(%{"content" => "b"}), %{"title" => "Renamed"})}
      end
    })

    data = "---\ntitle: Renamed\nparent: root\n---\nb"
    assert {:ok, _} = Backend.write("/engineering/start.md", data, %Ctx{})
  end

  test "remove page ok, failures, meta erofs, dir enotempty", %{ctx: _ctx} do
    put_pages([page()])

    StubClient.put(%{delete_page: :ok})
    assert :ok = Backend.remove("/engineering/start.md", %Ctx{})

    StubClient.put(%{delete_page: StubClient.error(500)})
    assert {:error, :eio} = Backend.remove("/engineering/start.md", %Ctx{})

    assert {:error, :erofs} = Backend.remove("/engineering/start.meta", %Ctx{})
    assert {:error, :enotempty} = Backend.remove("/engineering", %Ctx{})
    assert {:error, :enotempty} = Backend.remove("/", %Ctx{})
  end
end
