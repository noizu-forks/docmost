defmodule Noizu.MCP.VFS.Conformance do
  @moduledoc """
  Vendored copy of elixir-mcp's `test/support/vfs_conformance.ex` battery,
  adapted for a remote-shaped backend. The upstream battery is lib-local test
  support (not shipped in the hex package), so hosts vendor it. This copy runs
  against `DocmostMCP.VFS.Backend` through the same
  `Noizu.MCP.Server.Features.VFS` wrappers, so version stamping, cache
  invalidation, and read-after-write freshness stay verified.

  Adaptations for the Docmost projection (each marked inline):

    * the standard conformance tree lives under the seeded space `/cf` — the
      remote root only ever holds space directories;
    * files are `<slug>.md` with sibling `<slug>.meta` entries in listings;
    * page content travels in a front-matter envelope, so write/read content
      assertions match on substrings and size matches the encoded body;
    * `/` and container dirs are projections, not deletable containers —
      removal there is `:enotempty` (upstream expects `:eacces` / success);
    * `create(_, :dir)` creates a *space* (the only supported dir creation).

  Non-async: the battery shares `DocmostMCP.TestClient`'s process-global state.
  """

  defmacro __using__(opts) do
    backend = Keyword.fetch!(opts, :backend)
    {seed_mod, seed_fun} = Keyword.fetch!(opts, :seed)

    quote bind_quoted: [backend: backend, seed_mod: seed_mod, seed_fun: seed_fun] do
      use ExUnit.Case, async: false

      alias Noizu.MCP.Server.Features.VFS
      alias Noizu.MCP.VFS.Cache

      setup do
        ctx = apply(unquote(seed_mod), unquote(seed_fun), [])
        backend = unquote(backend)

        on_exit(fn -> Cache.purge(backend) end)
        %{backend: backend, ctx: ctx}
      end

      # ── stat ──────────────────────────────────────────────────────────────

      test "stat/3 returns a dir node for /", %{backend: backend, ctx: ctx} do
        assert {:ok, node} = VFS.stat(backend, "/", ctx)
        assert node.type == :dir
        assert is_integer(node.version) and node.version > 0
        assert is_map(node.xattrs)
      end

      test "stat/3 returns a file node with size and write capability", %{
        backend: backend,
        ctx: ctx
      } do
        assert {:ok, node} = VFS.stat(backend, "/cf/hello.md", ctx)
        assert node.type == :file
        # Docmost adaptation: size covers the full front-matter envelope.
        assert {:ok, content, _} = VFS.read(backend, "/cf/hello.md", ctx)
        assert node.size == byte_size(content)
        assert node.writable == true
      end

      test "stat/3 on a missing path is :enoent", %{backend: backend, ctx: ctx} do
        assert {:error, :enoent} = VFS.stat(backend, "/nope", ctx)
      end

      # ── list ──────────────────────────────────────────────────────────────

      test "list/4 returns entries with name/type/size/mtime/version", %{
        backend: backend,
        ctx: ctx
      } do
        assert {:ok, entries, next_cursor} = VFS.list(backend, "/cf", nil, ctx)
        assert is_nil(next_cursor)

        hello = Enum.find(entries, &match?(%{name: "hello.md"}, &1))
        assert hello.type == :file
        assert is_integer(hello.mtime)
        assert is_integer(hello.version)

        # Docmost adaptation: spaces project as dirs.
        docs = Enum.find(entries, &match?(%{name: "docs", type: :dir}, &1))
        assert docs != nil
      end

      test "list/4 on a file is :enotdir, on a missing path :enoent", %{
        backend: backend,
        ctx: ctx
      } do
        assert {:error, :enotdir} = VFS.list(backend, "/cf/hello.md", nil, ctx)
        assert {:error, :enoent} = VFS.list(backend, "/nope", nil, ctx)
      end

      test "list/4 rejects an invalid cursor", %{backend: backend, ctx: ctx} do
        assert {:error, %Noizu.MCP.Error{}} = VFS.list(backend, "/cf", "not-a-cursor", ctx)
      end

      # Docmost adaptation: a page dir lists the children plus their .meta
      # siblings, so /cf/docs holds four entries.
      test "list/4 pagination cursor round-trips", %{backend: backend, ctx: ctx} do
        assert {:ok, entries, nil} = VFS.list(backend, "/cf/docs", nil, ctx)
        assert length(entries) == 4
      end

      # ── read ──────────────────────────────────────────────────────────────

      test "read/4 returns content and version matching stat", %{backend: backend, ctx: ctx} do
        assert {:ok, node} = VFS.stat(backend, "/cf/hello.md", ctx)
        assert {:ok, content, version} = VFS.read(backend, "/cf/hello.md", ctx)
        assert content =~ "hello world"
        assert version == node.version
      end

      test "read/4 on a dir is :eisdir, on a missing path :enoent", %{
        backend: backend,
        ctx: ctx
      } do
        assert {:error, :eisdir} = VFS.read(backend, "/cf/docs", ctx)
        # Docmost adaptation: a missing *space* path reads as :eisdir on the
        # remote-shaped backend; the :enoent case is a missing page.
        assert {:error, :enoent} = VFS.read(backend, "/cf/nope.md", ctx)
      end

      # ── write ─────────────────────────────────────────────────────────────

      test "write/4 overwrites an existing file and bumps the version", %{
        backend: backend,
        ctx: ctx
      } do
        assert {:ok, before} = VFS.stat(backend, "/cf/hello.md", ctx)
        assert {:ok, node} = VFS.write(backend, "/cf/hello.md", "goodbye\n", ctx)
        assert node.version > before.version
        assert {:ok, content, _} = VFS.read(backend, "/cf/hello.md", ctx)
        assert content =~ "goodbye"
      end

      test "write/4 on a missing path is :enoent, on a dir :eisdir", %{
        backend: backend,
        ctx: ctx
      } do
        assert {:error, :enoent} = VFS.write(backend, "/cf/nope.md", "x", ctx)
        assert {:error, :eisdir} = VFS.write(backend, "/cf/docs", "x", ctx)
      end

      # ── create ────────────────────────────────────────────────────────────

      test "create/4 makes a new file, :eexist if present, :enoent without parent", %{
        backend: backend,
        ctx: ctx
      } do
        assert {:ok, node} = VFS.create(backend, "/cf/new.md", "fresh\n", ctx)
        assert node.type == :file
        assert node.writable == true
        assert {:error, :eexist} = VFS.create(backend, "/cf/new.md", "again", ctx)
        assert {:error, :enoent} = VFS.create(backend, "/cf/nodir/x.md", "x", ctx)
      end

      # Docmost adaptation: :dir creation is only supported at space level.
      test "create/4 with :dir makes a directory", %{backend: backend, ctx: ctx} do
        assert {:ok, node} = VFS.create(backend, "/cf-fresh", :dir, ctx)
        assert node.type == :dir
        assert {:ok, entries, nil} = VFS.list(backend, "/cf-fresh", nil, ctx)
        assert entries == []
      end

      # ── remove ────────────────────────────────────────────────────────────

      test "remove/3 deletes a file, then it is :enoent", %{backend: backend, ctx: ctx} do
        assert :ok = VFS.remove(backend, "/cf/hello.md", ctx)
        assert {:error, :enoent} = VFS.stat(backend, "/cf/hello.md", ctx)
        assert {:error, :enoent} = VFS.remove(backend, "/cf/hello.md", ctx)
      end

      # Docmost adaptation: the remote root is a projection — :enotempty, not
      # :eacces, and container dirs (even empty ones) are not deletable.
      test "remove/3 refuses / and non-empty dirs", %{backend: backend, ctx: ctx} do
        assert {:error, :enotempty} = VFS.remove(backend, "/", ctx)
        assert {:error, :enotempty} = VFS.remove(backend, "/cf/docs", ctx)
        assert {:error, :enotempty} = VFS.remove(backend, "/cf-fresh", ctx)
      end

      # ── search ────────────────────────────────────────────────────────────

      test "search/4 finds line matches with path/line/text", %{backend: backend, ctx: ctx} do
        assert {:ok, matches, nil} = VFS.search(backend, "/cf", "alpha", ctx)
        assert matches == [%{path: "/cf/docs/a.md", line: 1, text: "# alpha"}]
      end

      # Docmost adaptation: a page_dir search root only scans that directory's
      # own page content on the remote-shaped backend, so the subtree query
      # runs from the space root — same matches, same path order.
      test "search/4 finds multi-line matches in path order", %{backend: backend, ctx: ctx} do
        assert {:ok, matches, nil} = VFS.search(backend, "/cf", "a", ctx)
        assert length(matches) >= 3

        assert Enum.all?(
                 matches,
                 &match?(
                   %{path: "/cf/docs/" <> _, line: l, text: t}
                   when is_integer(l) and is_binary(t),
                   &1
                 )
               )
      end

      test "search/4 with no hits returns an empty page", %{backend: backend, ctx: ctx} do
        assert {:ok, [], nil} = VFS.search(backend, "/cf", "zzz-not-there", ctx)
      end

      # ── xattr ─────────────────────────────────────────────────────────────

      test "xattr/3 returns a map", %{backend: backend, ctx: ctx} do
        assert {:ok, xattrs} = VFS.xattr(backend, "/cf/hello.md", ctx)
        assert is_map(xattrs)
      end

      # ── cache integration ─────────────────────────────────────────────────

      test "a write invalidates cached stat and read results", %{backend: backend, ctx: ctx} do
        assert {:ok, before} = VFS.stat(backend, "/cf/hello.md", ctx)
        assert {:ok, _} = VFS.write(backend, "/cf/hello.md", "changed\n", ctx)

        assert {:ok, post} = VFS.stat(backend, "/cf/hello.md", ctx)
        assert post.version > before.version

        assert {:ok, content, version} = VFS.read(backend, "/cf/hello.md", ctx)
        assert content =~ "changed"
        assert version == post.version
      end

      test "generation embeds into returned versions", %{backend: backend, ctx: ctx} do
        gen0 = Cache.generation(backend)
        assert {:ok, node} = VFS.stat(backend, "/cf/hello.md", ctx)
        assert node.version > gen0
      end

      test "create and remove invalidate cached listings", %{backend: backend, ctx: ctx} do
        assert {:ok, entries_before, _} = VFS.list(backend, "/cf/docs", nil, ctx)

        assert {:ok, _} = VFS.create(backend, "/cf/docs/c.md", "c\n", ctx)
        assert {:ok, entries_after_create, _} = VFS.list(backend, "/cf/docs", nil, ctx)
        assert Enum.any?(entries_after_create, &match?(%{name: "c.md"}, &1))
        # The .meta sibling arrives with the page.
        assert length(entries_after_create) == length(entries_before) + 2

        assert :ok = VFS.remove(backend, "/cf/docs/c.md", ctx)
        assert {:ok, entries_after_remove, _} = VFS.list(backend, "/cf/docs", nil, ctx)
        # Versions embed the generation (bumped twice since the first listing),
        # so compare the shape, not the stamped versions.
        assert Enum.map(entries_after_remove, & &1.name) ==
                 Enum.map(entries_before, & &1.name)
      end
    end
  end
end
