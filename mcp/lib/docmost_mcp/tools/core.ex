defmodule DocmostMCP.Tools.Core do
  @moduledoc "Direct Docmost space, page, and sharing tools."
  use Noizu.MCP.Server.Toolkit, category: "Docmost"

  alias DocmostMCP.{Auth, Client, Config}
  alias DocmostMCP.VFS.MetaFile

  @mcp name: "docmost_spaces_list",
       description: "List Docmost spaces.",
       annotations: [read_only_hint: true],
       input: []
  def spaces_list(_args, ctx) do
    Auth.assume(ctx)
    with {:ok, rows} <- Client.list_spaces(),
         do: {:ok, %{spaces: DocmostMCP.Normalize.list(rows)}}
  end

  @mcp name: "docmost_pages_list",
       description: "List the page hierarchy for a space.",
       annotations: [read_only_hint: true],
       input: [space_id: [type: :string, required: true]]
  def pages_list(%{space_id: id}, ctx) do
    Auth.assume(ctx)
    with {:ok, rows} <- Client.list_pages(id),
         do: {:ok, %{pages: DocmostMCP.Normalize.list(rows)}}
  end

  @mcp name: "docmost_page_get",
       description: "Get a page as Markdown.",
       annotations: [read_only_hint: true],
       input: [page_id: [type: :string, required: true]]
  def page_get(%{page_id: id}, ctx) do
    Auth.assume(ctx)
    Client.get_page(id)
  end

  @mcp name: "docmost_page_create",
       description: "Create a Markdown page. Requires DOCMOST_MCP_WRITES=1.",
       input: [
         space_id: [type: :string, required: true],
         title: [type: :string, required: true],
         content: [type: :string, default: ""],
         parent_page_id: [type: :string]
       ]
  def page_create(args, ctx) do
    Auth.assume(ctx)
    write(fn ->
      Client.create_page(%{
        spaceId: args.space_id,
        title: args.title,
        content: args.content,
        # optional args arrive only when the caller passes them
        parentPageId: Map.get(args, :parent_page_id),
        format: "markdown"
      })
    end)
  end

  @mcp name: "docmost_page_update",
       description: "Replace a page's Markdown content. Requires DOCMOST_MCP_WRITES=1.",
       input: [
         page_id: [type: :string, required: true],
         content: [type: :string, required: true],
         title: [type: :string]
       ]
  def page_update(args, ctx) do
    Auth.assume(ctx)

    write(fn ->
        Client.update_page(args.page_id, %{
          content: args.content,
          title: Map.get(args, :title),
          format: "markdown",
          operation: "replace"
        })
      end)
  end

  @mcp name: "docmost_page_delete",
       description: "Soft-delete a page. Requires DOCMOST_MCP_WRITES=1.",
       annotations: [destructive_hint: true],
       input: [
         page_id: [type: :string, required: true],
         confirm: [type: :boolean, default: false]
       ]
  def page_delete(%{confirm: true, page_id: id}, ctx) do
    Auth.assume(ctx)
    write(fn -> Client.delete_page(id) end)
  end

  def page_delete(_, _ctx), do: {:error, "confirm=true is required"}

  @mcp name: "docmost_page_share",
       description:
         "Set a page public/private and return canonical YAML including its public URL. Inherited shares cannot be removed.",
       input: [
         page_id: [type: :string, required: true],
         share: [type: :enum, values: [:public, :private], required: true],
         include_sub_pages: [type: :boolean],
         search_indexing: [type: :boolean]
       ]
  def page_share(args, ctx) do
    Auth.assume(ctx)
    write(fn ->
      with {:ok, page} <- Client.get_page(args.page_id),
           # Only pass the settings the caller actually provided: the meta-file
           # guard rejects `share: private` combined with either key, so always
           # emitting the schema defaults would make every private toggle fail.
           yaml = share_yaml(args),
           {:ok, meta} <- MetaFile.apply(page, yaml) do
        {:ok, MetaFile.encode(meta)}
      end
    end)
  end

  @doc "Build the meta-file YAML for docmost_page_share from the tool args."
  def share_yaml(args) do
    ([{"share", to_string(args.share)}] ++
       Enum.map([:include_sub_pages, :search_indexing], fn key ->
         case Map.fetch(args, key) do
           {:ok, value} -> {Atom.to_string(key), value}
           :error -> nil
         end
       end))
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{v}" end)
    |> Kernel.<>("\n")
  end

  defp write(fun) do
    if Config.writes?(),
      do: normalize(fun.()),
      else: {:error, "writes disabled; set DOCMOST_MCP_WRITES=1"}
  end

  defp normalize(:ok), do: {:ok, %{ok: true}}
  defp normalize({:ok, _} = result), do: result

  defp normalize({:error, :eacces}),
    do: {:error, "operation would remove inherited access; change the ancestor instead"}

  defp normalize({:error, %DocmostMCP.Error{status: status, message: message}}),
    do: {:error, "Docmost request failed (#{status || "network"}): #{message}"}

  defp normalize({:error, _reason}), do: {:error, "Docmost request failed"}
end
