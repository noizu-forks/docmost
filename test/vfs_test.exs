defmodule DocmostMCP.VFSTest do
  use ExUnit.Case, async: false
  alias DocmostMCP.VFS.Backend
  alias Noizu.MCP.Ctx

  setup do
    {:ok, _} = DocmostMCP.TestClient.start()
    DocmostMCP.VersionStore.reset()
    %{ctx: %Ctx{}}
  end

  test "nested hierarchy resolves duplicate slugs beneath different parents", %{ctx: ctx} do
    pages = [
      %{
        "id" => "a",
        "slugId" => "alpha",
        "spaceId" => "s1",
        "title" => "Alpha",
        "content" => "A",
        "parentPageId" => nil
      },
      %{
        "id" => "b",
        "slugId" => "beta",
        "spaceId" => "s1",
        "title" => "Beta",
        "content" => "B",
        "parentPageId" => nil
      },
      %{
        "id" => "ac",
        "slugId" => "child",
        "spaceId" => "s1",
        "title" => "A Child",
        "content" => "under alpha",
        "parentPageId" => "a"
      },
      %{
        "id" => "bc",
        "slugId" => "child",
        "spaceId" => "s1",
        "title" => "B Child",
        "content" => "under beta",
        "parentPageId" => "b"
      }
    ]

    DocmostMCP.TestClient.put_pages(pages)
    assert {:ok, root, nil} = Backend.list("/engineering", nil, ctx)
    assert Enum.any?(root, &(&1.name == "alpha" and &1.type == :dir))

    assert {:ok, [%{name: "child.md"}, %{name: "child.meta"}], nil} =
             Backend.list("/engineering/alpha", nil, ctx)

    assert {:ok, alpha, _} = Backend.read("/engineering/alpha/child.md", ctx)
    assert {:ok, beta, _} = Backend.read("/engineering/beta/child.md", ctx)
    assert alpha =~ "under alpha"
    assert beta =~ "under beta"
    assert {:list_child_pages, "a"} in DocmostMCP.TestClient.calls()
    assert {:list_child_pages, "b"} in DocmostMCP.TestClient.calls()

    assert {:ok, matches, nil} = Backend.search("/engineering", "under alpha", ctx)
    assert [%{path: "/engineering/alpha/child.md"}] = matches
  end

  test "versions are stable until content changes and then increase", %{ctx: ctx} do
    assert {:ok, first} = Backend.stat("/engineering/start.md", ctx)
    assert {:ok, same} = Backend.stat("/engineering/start.md", ctx)
    assert first.version == same.version
    assert {:ok, _} = Backend.write("/engineering/start.md", "changed", ctx)
    assert {:ok, changed} = Backend.stat("/engineering/start.md", ctx)
    assert changed.version > first.version
  end

  test "lists spaces and paired page/meta files", %{ctx: ctx} do
    assert {:ok, [%{name: "engineering"}], nil} = Backend.list("/", nil, ctx)
    assert {:ok, entries, nil} = Backend.list("/engineering", nil, ctx)
    assert Enum.map(entries, & &1.name) == ["start.md", "start.meta"]
  end

  test "reads and updates Markdown page", %{ctx: ctx} do
    assert {:ok, content, _} = Backend.read("/engineering/start.md", ctx)
    assert content =~ "# Start"
    assert {:ok, _} = Backend.write("/engineering/start.md", "# Changed\n", ctx)
    assert {:ok, changed, _} = Backend.read("/engineering/start.md", ctx)
    assert changed =~ "# Changed"
  end

  test "meta public share refresh includes URL", %{ctx: ctx} do
    assert {:ok, _} = Backend.write("/engineering/start.meta", "share: public\n", ctx)
    assert {:ok, yaml, _} = Backend.read("/engineering/start.meta", ctx)
    assert yaml =~ ~s(share: "public")
    assert yaml =~ "https://docs.example.com/share/public-key/p/untitled-start"
  end

  test "server-provided publicUrl wins over local derivation", %{ctx: ctx} do
    DocmostMCP.TestClient.put_share("p1", %{
      "shared" => true,
      "id" => "sh1",
      "key" => "k",
      "level" => 0,
      "publicUrl" => "https://share.example.com/p/k"
    })

    assert {:ok, _} = Backend.write("/engineering/start.meta", "share: public\n", ctx)
    assert {:ok, yaml, _} = Backend.read("/engineering/start.meta", ctx)
    assert yaml =~ "https://share.example.com/p/k"
    refute yaml =~ "untitled-start"
  end

  test "unknown meta keys are rejected", %{ctx: ctx} do
    assert {:error, :eio} = Backend.write("/engineering/start.meta", "surprise: true\n", ctx)
  end

  test "duplicate page is eexist and empty control names are absent", %{ctx: ctx} do
    assert {:error, :eexist} = Backend.create("/engineering/start.md", "again", ctx)
    assert {:error, :enoent} = Backend.stat("/engineering/.md", ctx)
    assert {:error, :enoent} = Backend.stat("/engineering/.meta", ctx)
  end

  test "readonly meta keys are erofs", %{ctx: ctx} do
    assert {:error, :erofs} = Backend.write("/engineering/start.meta", "url: nope\n", ctx)
  end

  test "public share settings can be changed true to false", %{ctx: ctx} do
    DocmostMCP.TestClient.put_share("p1", %{
      "shared" => true,
      "id" => "sh1",
      "key" => "k",
      "level" => 0,
      "includeSubPages" => true,
      "searchIndexing" => true
    })

    assert {:ok, _} =
             Backend.write(
               "/engineering/start.meta",
               "share: public\ninclude_sub_pages: false\nsearch_indexing: false\n",
               ctx
             )

    assert {:ok, yaml, _} = Backend.read("/engineering/start.meta", ctx)
    assert yaml =~ "include_sub_pages: false"
    assert yaml =~ "search_indexing: false"
  end

  test "inherited-only share and restriction cannot be removed", %{ctx: ctx} do
    DocmostMCP.TestClient.put_share("p1", %{
      "shared" => true,
      "id" => "ancestor",
      "key" => "k",
      "level" => 1
    })

    assert {:error, :eacces} = Backend.write("/engineering/start.meta", "share: private\n", ctx)

    DocmostMCP.TestClient.put_access("p1", %{
      "restriction" => "inherited",
      "canAccess" => true,
      "canEdit" => false,
      "grants" => []
    })

    assert {:error, :eacces} = Backend.write("/engineering/start.meta", "access: open\n", ctx)
  end

  test "private share rejects share settings", %{ctx: ctx} do
    assert {:error, :eio} =
             Backend.write(
               "/engineering/start.meta",
               "share: private\ninclude_sub_pages: false\n",
               ctx
             )

    assert {:error, :eio} =
             Backend.write("/engineering/start.meta", "search_indexing: false\n", ctx)
  end

  test "canonical permissions use Docmost grant ids and removal deletes grants", %{ctx: ctx} do
    user = "11111111-1111-4111-8111-111111111111"

    DocmostMCP.TestClient.put_access("p1", %{
      "restriction" => "direct",
      "canAccess" => true,
      "canEdit" => true,
      "grants" => [%{"id" => "g-1", "type" => "user", "principalId" => user, "role" => "reader"}]
    })

    assert {:ok, yaml, _} = Backend.read("/engineering/start.meta", ctx)
    assert yaml =~ ~s(access: "direct")
    assert yaml =~ user

    assert {:ok, _} =
             Backend.write(
               "/engineering/start.meta",
               "permissions: []\npermissions_mode: replace\n",
               ctx
             )

    assert {:remove_grant, "p1", "g-1"} in DocmostMCP.TestClient.calls()
  end

  test "next cursor is read from Docmost data meta shape" do
    assert "next" == DocmostMCP.Normalize.next_cursor(%{"meta" => %{"nextCursor" => "next"}})
  end

  test "grouped permissions expand by principal, batch adds and grant-id updates", %{ctx: ctx} do
    user1 = "11111111-1111-4111-8111-111111111111"
    user2 = "22222222-2222-4222-8222-222222222222"
    group = "33333333-3333-4333-8333-333333333333"

    DocmostMCP.TestClient.put_access("p1", %{
      "restriction" => "direct",
      "canAccess" => true,
      "canEdit" => true,
      "grants" => [
        %{"id" => "g-u1", "type" => "user", "principalId" => user1, "role" => "reader"}
      ]
    })

    yaml = """
    permissions_mode: replace
    permissions:
      - role: writer
        user_ids: [#{user1}, #{user2}]
      - role: reader
        group_ids: [#{group}]
    """

    assert {:ok, _} = Backend.write("/engineering/start.meta", yaml, ctx)
    calls = DocmostMCP.TestClient.calls()

    assert {:update_grant, "p1", "g-u1", "writer"} in calls

    assert Enum.any?(calls, fn call ->
             match?(
               {:add_grants, "p1",
                [
                  %{type: "user", principalId: ^user2, role: "writer"},
                  %{type: "group", principalId: ^group, role: "reader"}
                ]},
               call
             )
           end)

    refute Enum.any?(calls, &match?({:remove_grant, _, _}, &1))
  end
end
