defmodule DocmostMCP.Client.Req do
  @moduledoc false

  @behaviour DocmostMCP.ClientBehaviour

  alias DocmostMCP.{Config, Error}

  @impl true
  def list_spaces(cursor), do: request(:post, "/spaces", compact(%{limit: 100, cursor: cursor}))
  @impl true
  def get_space(id), do: request(:post, "/spaces/info", %{spaceId: id})
  @impl true
  def create_space(attrs), do: request(:post, "/spaces/create", attrs)
  @impl true
  def list_pages(space_id, cursor),
    do:
      request(
        :post,
        "/pages/sidebar-pages",
        compact(%{spaceId: space_id, limit: 100, cursor: cursor})
      )

  @impl true
  def list_child_pages(page_id, cursor),
    do:
      request(
        :post,
        "/pages/sidebar-pages",
        compact(%{pageId: page_id, limit: 100, cursor: cursor})
      )

  @impl true
  def get_page(id),
    do:
      request(:post, "/pages/info", %{
        pageId: id,
        includeSpace: true,
        includeContent: true,
        format: "markdown"
      })

  @impl true
  def create_page(attrs), do: request(:post, "/pages/create", create_content_options(attrs))
  @impl true
  def update_page(id, attrs),
    do:
      request(
        :post,
        "/pages/update",
        attrs |> Map.put(:pageId, id) |> update_content_options()
      )

  @impl true
  def delete_page(id) do
    case request(:post, "/pages/delete", %{pageId: id, permanentlyDelete: false}) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @impl true
  def get_share(id), do: request(:post, "/shares/for-page", %{pageId: id})
  @impl true
  def create_share(attrs), do: request(:post, "/shares/create", attrs)
  @impl true
  def update_share(attrs), do: request(:post, "/shares/update", attrs)
  @impl true
  def delete_share(id), do: request(:post, "/shares/delete", %{shareId: id})
  @impl true
  # Core has no /pages/permission-info in this fork base; the v1 access
  # surface carries the same signal (restriction: none|direct|inherited).
  def permission_info(id) do
    case request(:get, "/v1/pages/#{id}/access", nil) do
      {:ok, %{"restriction" => restriction} = access} when is_binary(restriction) ->
        {:ok,
         access
         |> Map.put("hasDirectRestriction", restriction == "direct")
         |> Map.put("hasInheritedRestriction", restriction == "inherited")}

      {:ok, other} ->
        {:ok, other}

      error ->
        error
    end
  end
  @impl true
  # Core has no POST /pages/permissions here; grants come from the v1
  # access surface nested under the restriction summary.
  def list_permissions(id, cursor) do
    qs = if cursor in [nil, ""], do: "", else: "?cursor=\#{URI.encode_www_form(cursor)}"

    case request(:get, "/v1/pages/\#{id}/access\#{qs}", nil) do
      {:ok, %{"grants" => grants}} -> {:ok, grants}
      {:ok, _} -> {:ok, %{"data" => [], "meta" => %{"nextCursor" => nil}}}
      error -> error
    end
  end

  @impl true
  def restrict_page(id), do: request(:post, "/pages/restrict", %{pageId: id})
  @impl true
  def remove_restriction(id), do: request(:post, "/pages/remove-restriction", %{pageId: id})
  @impl true
  def add_permission(attrs), do: request(:post, "/pages/add-permission", attrs)
  @impl true
  def update_permission(attrs), do: request(:post, "/pages/update-permission", attrs)
  @impl true
  def remove_permission(attrs), do: request(:post, "/pages/remove-permission", attrs)

  defp request(method, path, body) do
    options =
      Keyword.merge(Config.req_options(),
        method: method,
        url: Config.api_url() <> path,
        headers: headers()
      )

    options = if body, do: Keyword.put(options, :json, body), else: options

    case Req.request(options) do
      {:ok, %{status: status, body: %{"success" => false} = response}}
      when status in 200..299 ->
        {:error, Error.from_response(response["status"] || status, response)}

      {:ok, %{status: status, body: response}} when status in 200..299 ->
        {:ok, unwrap(response)}

      {:ok, %{status: status, body: response}} ->
        {:error, Error.from_response(status, response)}

      {:error, reason} ->
        {:error, %Error{message: "Docmost request failed", details: reason}}
    end
  end

  defp headers do
    [
      {"authorization", "Bearer " <> bearer()},
      {"accept", "application/json"},
      {"user-agent", "docmost-mcp/0.1.0"}
    ]
  end

  # Fork session-identity auth: prefer the verified docmost session JWT of the
  # signed-in user (see DocmostMCP.Auth); fall back to the static shared key
  # for stdio/CLI callers with no session.
  defp bearer do
    case DocmostMCP.Auth.current_bearer() do
      token when is_binary(token) and token != "" -> token
      _ -> Config.api_key()
    end
  end

  defp unwrap(%{"data" => data}), do: data
  defp unwrap(%{data: data}), do: data
  defp unwrap(nil), do: %{}
  defp unwrap(other), do: other
  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp create_content_options(attrs) do
    if Map.has_key?(attrs, :content) or Map.has_key?(attrs, "content") do
      Map.put(attrs, :format, "markdown")
    else
      attrs
    end
  end

  defp update_content_options(attrs) do
    if Map.has_key?(attrs, :content) or Map.has_key?(attrs, "content") do
      attrs |> Map.put(:format, "markdown") |> Map.put_new(:operation, "replace")
    else
      attrs
    end
  end
end
