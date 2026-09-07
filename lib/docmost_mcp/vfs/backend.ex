defmodule DocmostMCP.VFS.Backend do
  @moduledoc "Docmost spaces/pages projected as directories, Markdown files, and YAML control metadata."
  use Noizu.MCP.VFS

  alias DocmostMCP.{Client, Config, Normalize}
  alias DocmostMCP.VFS.{MetaFile, PageFile, Path}
  alias Noizu.MCP.Server.Features.Pagination
  alias Noizu.MCP.VFS

  @impl true
  def __mcp_vfs__(:describe),
    do: "Docmost spaces and wiki pages. Write `<page>.meta` to manage sharing and access."

  @impl true
  def stat(path, _ctx) do
    with {:ok, kind} <- Path.parse(path), do: stat_kind(kind)
  end

  @impl true
  def list(path, cursor, _ctx) do
    with {:ok, kind} <- Path.parse(path), do: list_kind(kind, cursor)
  end

  @impl true
  def read(path, _ctx) do
    with {:ok, kind} <- Path.parse(path), do: read_kind(kind)
  end

  @impl true
  def create(path, data, _ctx) do
    with true <- Config.writes?() || {:error, :eacces},
         {:ok, kind} <- Path.parse(path) do
      create_kind(kind, data)
    else
      false -> {:error, :eacces}
      error -> error
    end
  end

  @impl true
  def write(path, data, _ctx) do
    with true <- Config.writes?() || {:error, :eacces},
         {:ok, kind} <- Path.parse(path) do
      write_kind(kind, data)
    else
      false -> {:error, :eacces}
      error -> error
    end
  end

  @impl true
  def remove(path, _ctx) do
    with true <- Config.writes?() || {:error, :eacces},
         {:ok, kind} <- Path.parse(path) do
      remove_kind(kind)
    else
      false -> {:error, :eacces}
      error -> error
    end
  end

  @impl true
  def search(root, query, _ctx) do
    with {:ok, kind} <- Path.parse(root),
         {:ok, pages} <- pages_for(kind) do
      needle = String.downcase(query)

      matches =
        Enum.flat_map(pages, fn {space, page, refs} ->
          (Normalize.value(page, :content) || "")
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.flat_map(fn {line, number} ->
            if String.contains?(String.downcase(line), needle) do
              [
                %{
                  path: "/#{Normalize.slug(space)}/#{Enum.join(refs, "/")}.md",
                  line: number,
                  text: line
                }
              ]
            else
              []
            end
          end)
        end)

      {:ok, matches, nil}
    end
  end

  @impl true
  def xattr(path, ctx) do
    case stat(path, ctx) do
      {:ok, %VFS{xattrs: attrs}} -> {:ok, attrs}
      error -> error
    end
  end

  defp stat_kind(:root), do: {:ok, dir()}

  defp stat_kind({:space, ref}) do
    with {:ok, space} <- space(ref), do: {:ok, dir(%{"id" => Normalize.id(space)})}
  end

  defp stat_kind({:page_dir, space_ref, page_refs}) do
    with {:ok, _space, _page} <- page(space_ref, page_refs), do: {:ok, dir()}
  end

  defp stat_kind({kind, space_ref, page_refs}) when kind in [:page, :meta] do
    with {:ok, _space, page} <- page(space_ref, page_refs),
         {:ok, content} <- content(kind, page) do
      node_version = path_version(kind, space_ref, page_refs, content)
      {:ok, file(content, node_version, %{"id" => Normalize.id(page), "kind" => to_string(kind)})}
    end
  end

  defp list_kind(:root, cursor) do
    with {:ok, raw} <- all_spaces() do
      raw
      |> Enum.map(&entry(Normalize.slug(&1), :dir, version(&1)))
      |> paginate(cursor)
    else
      _ -> {:error, :eio}
    end
  end

  defp list_kind({:space, ref}, cursor) do
    with {:ok, space} <- space(ref), {:ok, pages} <- page_tree(space) do
      paginate(page_entries(pages), cursor)
    end
  end

  defp list_kind({:page_dir, space_ref, refs}, cursor) do
    with {:ok, _space, page} <- page(space_ref, refs) do
      paginate(page_entries(children(page)), cursor)
    end
  end

  defp list_kind(_, _), do: {:error, :enotdir}

  defp read_kind(:root), do: {:error, :eisdir}
  defp read_kind({:space, _}), do: {:error, :eisdir}

  defp read_kind({:page_dir, _, _}), do: {:error, :eisdir}

  defp read_kind({kind, space_ref, page_refs}) do
    with {:ok, _space, page} <- page(space_ref, page_refs),
         {:ok, body} <- content(kind, page),
         do: {:ok, body, path_version(kind, space_ref, page_refs, body)}
  end

  defp create_kind({:space, ref}, :dir) do
    case Client.create_space(%{name: humanize(ref), slug: ref}) do
      {:ok, space} -> {:ok, dir(%{"id" => Normalize.id(space)})}
      _ -> {:error, :eio}
    end
  end

  defp create_kind({:page, space_ref, page_refs}, data) when is_binary(data) do
    page_ref = List.last(page_refs)
    parent_refs = Enum.drop(page_refs, -1)

    with {:ok, space} <- space(space_ref),
         {:ok, siblings, parent_id} <- siblings(space, parent_refs),
         nil <- find_in(siblings, page_ref),
         {:ok, meta, body} <- PageFile.decode(data),
         {:ok, page} <-
           Client.create_page(%{
             spaceId: Normalize.id(space),
             title: meta["title"] || humanize(page_ref),
             parentPageId: meta["parent"] || parent_id,
             content: body
           }) do
      encoded = PageFile.encode(page)

      {:ok,
       file(encoded, path_version(:page, space_ref, page_refs, encoded), %{
         "id" => Normalize.id(page)
       })}
    else
      %{} -> {:error, :eexist}
      {:error, :enoent} -> {:error, :enoent}
      _ -> {:error, :eio}
    end
  end

  defp create_kind({:meta, _, _}, _), do: {:error, :eexist}
  defp create_kind(_, _), do: {:error, :enosys}

  defp write_kind({:page, space_ref, page_refs}, data) do
    with {:ok, _space, page} <- page(space_ref, page_refs),
         {:ok, meta, body} <- PageFile.decode(data),
         attrs =
           %{content: body, operation: "replace"}
           |> put(:title, meta["title"])
           |> put(:parentPageId, meta["parent"]),
         {:ok, updated} <- Client.update_page(Normalize.id(page), attrs) do
      encoded = PageFile.encode(updated)

      {:ok,
       file(encoded, path_version(:page, space_ref, page_refs, encoded), %{
         "id" => Normalize.id(updated)
       })}
    else
      {:error, :enoent} -> {:error, :enoent}
      _ -> {:error, :eio}
    end
  end

  defp write_kind({:meta, space_ref, page_refs}, data) do
    with {:ok, _space, page} <- page(space_ref, page_refs),
         {:ok, meta} <- MetaFile.apply(page, data) do
      body = MetaFile.encode(meta)

      {:ok,
       file(body, path_version(:meta, space_ref, page_refs, body), %{
         "id" => Normalize.id(page),
         "url" => meta.url
       })}
    end
  end

  defp write_kind(_, _), do: {:error, :eisdir}

  defp remove_kind({:page, space_ref, page_refs}) do
    with {:ok, _space, page} <- page(space_ref, page_refs) do
      case Client.delete_page(Normalize.id(page)) do
        :ok -> :ok
        _ -> {:error, :eio}
      end
    end
  end

  defp remove_kind({:meta, _, _}), do: {:error, :erofs}
  defp remove_kind(_), do: {:error, :enotempty}

  defp content(:page, page), do: {:ok, PageFile.encode(page)}

  defp content(:meta, page) do
    with {:ok, meta} <- MetaFile.read(page), do: {:ok, MetaFile.encode(meta)}
  end

  defp space(ref) do
    with {:ok, raw} <- all_spaces(),
         space when not is_nil(space) <-
           Enum.find(raw, &(Normalize.slug(&1) == ref or Normalize.id(&1) == ref)) do
      {:ok, space}
    else
      _ -> {:error, :enoent}
    end
  end

  defp page(space_ref, page_refs) do
    with {:ok, space} <- space(space_ref),
         {:ok, page} <- resolve_page(space, List.wrap(page_refs)),
         {:ok, full} <- Client.get_page(Normalize.id(page)) do
      {:ok, space, Map.put(full, "children", children(page))}
    end
  end

  defp page_tree(space) do
    case collect_page_tree(Normalize.id(space), nil, [], MapSet.new()) do
      {:ok, pages} -> {:ok, pages}
      error -> error
    end
  end

  defp resolve_page(space, refs) do
    with {:ok, roots} <- page_tree(space) do
      Enum.reduce_while(refs, {:ok, nil, roots}, fn ref, {:ok, _parent, nodes} ->
        case find_in(nodes, ref) do
          nil -> {:halt, {:error, :enoent}}
          page -> {:cont, {:ok, page, children(page)}}
        end
      end)
      |> case do
        {:ok, nil, _} -> {:error, :enoent}
        {:ok, page, _} -> {:ok, page}
        error -> error
      end
    end
  end

  defp siblings(space, []), do: with({:ok, roots} <- page_tree(space), do: {:ok, roots, nil})

  defp siblings(space, parents) do
    with {:ok, parent} <- resolve_page(space, parents),
         do: {:ok, children(parent), Normalize.id(parent)}
  end

  defp find_in(nodes, ref),
    do: Enum.find(nodes, &(Normalize.slug(&1) == ref or Normalize.id(&1) == ref))

  defp children(page), do: Normalize.list(Normalize.value(page, :children))

  defp page_entries(pages) do
    Enum.flat_map(pages, fn page ->
      slug = Normalize.slug(page)

      files = [
        entry(slug <> ".md", :file, version(page)),
        entry(slug <> ".meta", :file, version(page))
      ]

      if children(page) == [], do: files, else: files ++ [entry(slug, :dir, version(page))]
    end)
  end

  defp all_pages(space) do
    with {:ok, tree} <- page_tree(space), do: {:ok, flatten_paths(tree, [])}
  end

  defp flatten_paths(items, prefix) do
    Enum.flat_map(items, fn item ->
      refs = prefix ++ [Normalize.slug(item)]
      [{item, refs} | flatten_paths(children(item), refs)]
    end)
  end

  defp pages_for(:root) do
    with {:ok, raw} <- all_spaces() do
      pairs =
        Enum.flat_map(raw, fn s ->
          case all_pages(s) do
            {:ok, ps} -> Enum.map(ps, fn {page, refs} -> {s, page, refs} end)
            _ -> []
          end
        end)

      {:ok, pairs}
    end
  end

  defp pages_for({:space, ref}) do
    with {:ok, s} <- space(ref),
         {:ok, ps} <- all_pages(s),
         do: {:ok, Enum.map(ps, fn {page, refs} -> {s, page, refs} end)}
  end

  defp pages_for({_, s, p}) do
    with {:ok, space, page} <- page(s, p), do: {:ok, [{space, page, p}]}
  end

  defp paginate(entries, cursor) do
    case Pagination.paginate(entries, cursor) do
      {:ok, page, next} -> {:ok, page, next}
      error -> error
    end
  end

  defp all_spaces, do: collect_spaces(nil, [], MapSet.new())

  defp collect_spaces(cursor, acc, seen) do
    if cursor && MapSet.member?(seen, cursor),
      do: {:error, :eio},
      else: collect_spaces_page(cursor, acc, seen)
  end

  defp collect_spaces_page(cursor, acc, seen) do
    case Client.list_spaces(cursor) do
      {:ok, raw} ->
        rows = Normalize.list(raw)
        next = Normalize.next_cursor(raw)

        if next,
          do: collect_spaces(next, acc ++ rows, MapSet.put(seen, cursor)),
          else: {:ok, acc ++ rows}

      {:error, error} ->
        {:error, errno(error)}
    end
  end

  defp collect_page_tree(space, cursor, acc, seen) do
    if cursor && MapSet.member?(seen, cursor),
      do: {:error, :eio},
      else: collect_page_tree_page(space, cursor, acc, seen)
  end

  defp collect_page_tree_page(space, cursor, acc, seen) do
    case Client.list_pages(space, cursor) do
      {:ok, raw} ->
        rows = Normalize.list(raw)
        next = Normalize.next_cursor(raw)

        if next,
          do: collect_page_tree(space, next, acc ++ rows, MapSet.put(seen, cursor)),
          else: hydrate_children(acc ++ rows, MapSet.new())

      {:error, error} ->
        {:error, errno(error)}
    end
  end

  defp hydrate_children(rows, ancestors) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      id = Normalize.id(row)

      if is_nil(id) or MapSet.member?(ancestors, id) do
        {:halt, {:error, :eio}}
      else
        case collect_children(id, nil, [], MapSet.new()) do
          {:ok, children} ->
            case hydrate_children(children, MapSet.put(ancestors, id)) do
              {:ok, nested} -> {:cont, {:ok, acc ++ [Map.put(row, "children", nested)]}}
              error -> {:halt, error}
            end

          error ->
            {:halt, error}
        end
      end
    end)
  end

  defp collect_children(page, cursor, acc, cursors) do
    if cursor && MapSet.member?(cursors, cursor) do
      {:error, :eio}
    else
      case Client.list_child_pages(page, cursor) do
        {:ok, raw} ->
          rows = Normalize.list(raw)
          next = Normalize.next_cursor(raw)

          if next,
            do: collect_children(page, next, acc ++ rows, MapSet.put(cursors, cursor)),
            else: {:ok, acc ++ rows}

        {:error, error} ->
          {:error, errno(error)}
      end
    end
  end

  defp errno(%DocmostMCP.Error{status: status}) when status in [401, 403], do: :eacces
  defp errno(%DocmostMCP.Error{status: 404}), do: :enoent
  defp errno(_), do: :eio

  defp dir(attrs \\ %{}),
    do: %VFS{type: :dir, mtime: 0, version: 1, writable: Config.writes?(), xattrs: attrs}

  defp file(content, version, attrs),
    do: %VFS{
      type: :file,
      size: byte_size(content),
      mtime: version,
      version: version,
      writable: Config.writes?(),
      xattrs: attrs
    }

  defp entry(name, type, version),
    do: %{name: name, type: type, size: 0, mtime: version, version: version}

  defp version(row),
    do: Normalize.value(row, :version) || timestamp(Normalize.value(row, :updatedAt)) || 1

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.to_unix(dt, :millisecond)
      _ -> nil
    end
  end

  defp timestamp(_), do: nil

  defp path_version(kind, space, refs, content) do
    path = Enum.join([to_string(kind), space | refs], "/")
    DocmostMCP.VersionStore.version(path, :erlang.phash2(content))
  end

  defp humanize(ref),
    do:
      ref
      |> String.replace(~r/[-_]+/, " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end
