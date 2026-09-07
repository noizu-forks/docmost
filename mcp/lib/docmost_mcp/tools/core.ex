defmodule DocmostMCP.Tools.Core do
  @moduledoc "Direct Docmost space, page, and sharing tools."
  use Noizu.MCP.Server.Toolkit, category: "Docmost"

  alias DocmostMCP.{Client, Config}
  alias DocmostMCP.VFS.MetaFile

  @mcp name: "docmost_spaces_list",
       description: "List Docmost spaces.",
       annotations: [read_only_hint: true],
       input: []
  def spaces_list(_args, _ctx) do
    with {:ok, rows} <- Client.list_spaces(),
         do: {:ok, %{spaces: DocmostMCP.Normalize.list(rows)}}
  end

  @mcp name: "docmost_pages_list",
       description: "List the page hierarchy for a space.",
       annotations: [read_only_hint: true],
       input: [space_id: [type: :string, required: true]]
  def pages_list(%{space_id: id}, _ctx) do
    with {:ok, rows} <- Client.list_pages(id),
         do: {:ok, %{pages: DocmostMCP.Normalize.list(rows)}}
  end

  @mcp name: "docmost_page_get",
       description: "Get a page as Markdown.",
       annotations: [read_only_hint: true],
       input: [page_id: [type: :string, required: true]]
  def page_get(%{page_id: id}, _ctx), do: Client.get_page(id)

  @mcp name: "docmost_page_create",
       description: "Create a Markdown page. Requires DOCMOST_MCP_WRITES=1.",
       input: [
         space_id: [type: :string, required: true],
         title: [type: :string, required: true],
         content: [type: :string, default: ""],
         parent_page_id: [type: :string]
       ]
  def page_create(args, _ctx) do
    write(fn ->
      Client.create_page(%{
        spaceId: args.space_id,
        title: args.title,
        content: args.content,
        parentPageId: args.parent_page_id,
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
  def page_update(args, _ctx),
    do:
      write(fn ->
        Client.update_page(args.page_id, %{
          content: args.content,
          title: args.title,
          format: "markdown",
          operation: "replace"
        })
      end)

  @mcp name: "docmost_page_delete",
       description: "Soft-delete a page. Requires DOCMOST_MCP_WRITES=1.",
       annotations: [destructive_hint: true],
       input: [
         page_id: [type: :string, required: true],
         confirm: [type: :boolean, default: false]
       ]
  def page_delete(%{confirm: true, page_id: id}, _ctx),
    do: write(fn -> Client.delete_page(id) end)

  def page_delete(_, _ctx), do: {:error, "confirm=true is required"}

  @mcp name: "docmost_page_share",
       description:
         "Set a page public/private and return canonical YAML including its public URL. Inherited shares cannot be removed.",
       input: [
         page_id: [type: :string, required: true],
         share: [type: :enum, values: [:public, :private], required: true],
         include_sub_pages: [type: :boolean, default: false],
         search_indexing: [type: :boolean, default: false]
       ]
  def page_share(args, _ctx) do
    write(fn ->
      with {:ok, page} <- Client.get_page(args.page_id),
           yaml =
             "share: #{args.share}\ninclude_sub_pages: #{args.include_sub_pages}\nsearch_indexing: #{args.search_indexing}\n",
           {:ok, meta} <- MetaFile.apply(page, yaml) do
        {:ok, MetaFile.encode(meta)}
      end
    end)
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
