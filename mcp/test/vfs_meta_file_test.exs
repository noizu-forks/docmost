defmodule DocmostMCP.VFSMetaFileTest do
  use ExUnit.Case, async: false

  alias DocmostMCP.StubClient
  alias DocmostMCP.VFS.MetaFile

  @page %{"id" => "p1", "slugId" => "start", "spaceId" => "s1", "title" => "Start"}

  setup do
    {:ok, _} = DocmostMCP.TestClient.start()
    :ok
  end

  defp access(grants \\ [], restriction \\ "none") do
    %{"restriction" => restriction, "canAccess" => true, "canEdit" => true, "grants" => grants}
  end

  test "apply is eacces when writes are disabled" do
    Application.put_env(:docmost_mcp, :writes, false)

    on_exit(fn -> Application.put_env(:docmost_mcp, :writes, true) end)

    assert {:error, :eacces} = MetaFile.apply(@page, "share: public\n")
  end

  test "apply rejects invalid yaml" do
    assert {:error, _} = MetaFile.apply(@page, "[unclosed\n")
  end

  test "validate rejects bad access, mode, and permission shapes" do
    Application.put_env(:docmost_mcp, :client, StubClient)
    StubClient.put(%{get_share: {:ok, %{"shared" => false}}, get_access: {:ok, access()}})

    on_exit(fn ->
      Application.put_env(:docmost_mcp, :client, DocmostMCP.TestClient)
      StubClient.clear()
    end)

    user = "11111111-1111-4111-8111-111111111111"

    assert {:error, :eio} = MetaFile.apply(@page, "access: secret\n")
    assert {:error, :eio} = MetaFile.apply(@page, "permissions_mode: merge\n")
    assert {:error, :eio} = MetaFile.apply(@page, "permissions: 7\n")

    assert {:error, :eio} =
             MetaFile.apply(@page, "permissions:\n  - role: admin\n    user_ids: [#{user}]\n")

    assert {:error, :eio} =
             MetaFile.apply(@page, "permissions:\n  - role: writer\n    user_ids: []\n")

    assert {:error, :eio} =
             MetaFile.apply(
               @page,
               "permissions:\n  - role: writer\n    user_ids: [#{user}]\n    group_ids: [#{user}]\n"
             )

    assert {:error, :eio} =
             MetaFile.apply(@page, "permissions:\n  - role: writer\n    user_ids: [nope]\n")

    too_many =
      Enum.map_join(1..26, "\n", fn _ -> "  - role: writer\n    user_ids: [#{user}]" end)

    assert {:error, :eio} = MetaFile.apply(@page, "permissions:\n" <> too_many <> "\n")

    assert {:error, :eio} =
             MetaFile.apply(
               @page,
               "permissions:\n  - role: writer\n    group_ids: [" <>
                 Enum.map_join(1..26, ", ", fn _ -> "\"#{user}\"" end) <> "]\n"
             )
  end

  test "read and apply with grant envelopes and server publicUrl" do
    Application.put_env(:docmost_mcp, :client, StubClient)
    user = "11111111-1111-4111-8111-111111111111"

    StubClient.put(%{
      get_share: fn [_id] ->
        {:ok, %{"shared" => true, "key" => "k", "level" => 0, "publicUrl" => "https://srv/p/k"}}
      end,
      get_access: fn [_id, cursor] ->
        if cursor do
          {:ok, %{"restriction" => "none", "grants" => %{"data" => [], "meta" => %{}}}}
        else
          {:ok,
           %{
             "restriction" => "direct",
             "grants" => %{
               "data" => [%{"id" => "g-1", "type" => "user", "principalId" => user}],
               "meta" => %{"nextCursor" => "c1"}
             }
           }}
        end
      end
    })

    on_exit(fn ->
      Application.put_env(:docmost_mcp, :client, DocmostMCP.TestClient)
      StubClient.clear()
    end)

    assert {:ok, meta} = MetaFile.read(@page)
    assert meta.share == "public"
    assert meta.url == "https://srv/p/k"
    # restriction comes from the last access page
    assert meta.access == "open"

    assert [%{"grant_id" => "g-1", "role" => "reader", "type" => "user", "id" => ^user}] =
             meta.permissions

    yaml = MetaFile.encode(meta)
    assert yaml =~ "url: \"https://srv/p/k\""
    refute yaml =~ "grant_id"

    # grant cursor loop is eio
    StubClient.put(%{
      get_access: fn [_id, _cursor] ->
        {:ok,
         %{"restriction" => "none", "grants" => %{"data" => [], "meta" => %{"nextCursor" => "c"}}}}
      end
    })

    assert {:error, :eio} = MetaFile.read(@page)
  end

  test "public url falls back to local derivation and nil without key" do
    Application.put_env(:docmost_mcp, :client, StubClient)

    StubClient.put(%{
      get_share: {:ok, %{"shared" => true, "key" => "k", "level" => 0}},
      get_access: {:ok, access()}
    })

    on_exit(fn ->
      Application.put_env(:docmost_mcp, :client, DocmostMCP.TestClient)
      StubClient.clear()
    end)

    assert {:ok, meta} = MetaFile.read(@page)
    assert meta.url == "https://docs.example.com/share/k/p/untitled-start"

    StubClient.put(%{get_share: {:ok, %{"shared" => true, "level" => 0}}})
    assert {:ok, meta} = MetaFile.read(@page)
    assert meta.url == nil
  end

  test "share private upsert and 404 tolerance" do
    Application.put_env(:docmost_mcp, :client, StubClient)

    StubClient.put(%{
      get_share: fn [_id] ->
        {:ok, %{"shared" => true, "key" => "k", "level" => 0}}
      end,
      get_access: {:ok, access()},
      update_share: fn [_id, attrs] ->
        assert attrs == %{shared: false}
        {:ok, %{}}
      end
    })

    on_exit(fn ->
      Application.put_env(:docmost_mcp, :client, DocmostMCP.TestClient)
      StubClient.clear()
    end)

    assert {:ok, _} = MetaFile.apply(@page, "share: private\n")
  end

  test "apply access restricted then open toggles restriction off" do
    Application.put_env(:docmost_mcp, :client, StubClient)

    StubClient.put(%{
      get_share: {:ok, %{"shared" => false}},
      get_access: {:ok, access([])},
      set_restriction: fn [_id, restricted] ->
        assert restricted == true
        {:ok, %{}}
      end
    })

    on_exit(fn ->
      Application.put_env(:docmost_mcp, :client, DocmostMCP.TestClient)
      StubClient.clear()
    end)

    assert {:ok, _} = MetaFile.apply(@page, "access: restricted\n")

    # Opening a direct-restricted page sends restriction=false.
    StubClient.put(%{
      get_access: {:ok, access([], "direct")},
      set_restriction: fn [_id, restricted] ->
        assert restricted == false
        {:ok, %{}}
      end
    })

    assert {:ok, _} = MetaFile.apply(@page, "access: open\n")
  end
end
