defmodule DocmostMCP.Client.Req do
  @moduledoc false

  @behaviour DocmostMCP.ClientBehaviour

  alias DocmostMCP.{Config, Error}

  @impl true
  def list_spaces(cursor), do: get("/spaces", %{limit: 100, cursor: cursor})

  @impl true
  def get_space(id), do: get("/spaces/#{id}")

  @impl true
  def create_space(attrs), do: post("/spaces", attrs)

  @impl true
  def list_pages(space_id, cursor),
    do: get("/spaces/#{space_id}/pages", %{limit: 100, cursor: cursor})

  @impl true
  def list_child_pages(page_id, cursor),
    do: get("/pages/#{page_id}/children", %{limit: 100, cursor: cursor})

  @impl true
  def get_page(id), do: get("/pages/#{id}")

  @impl true
  def create_page(attrs) do
    {space_id, attrs} = Map.pop(attrs, :spaceId)
    post("/spaces/#{space_id}/pages", rename_parent(attrs))
  end

  @impl true
  def update_page(id, attrs) do
    meta =
      attrs
      |> rename_parent()
      |> Map.take([:title, :parentId])
      |> compact()

    with {:ok, page} <- patch_meta(id, meta) do
      if Map.has_key?(attrs, :content),
        do: put_content(id, attrs),
        else: {:ok, page}
    end
  end

  @impl true
  def delete_page(id) do
    case request(:delete, "/pages/#{id}", nil, []) do
      {:ok, _} -> :ok
      {:error, %Error{status: 404}} -> :ok
      error -> error
    end
  end

  @impl true
  def get_share(id), do: get("/pages/#{id}/share")

  @impl true
  def update_share(id, attrs), do: put("/pages/#{id}/share", attrs)

  @impl true
  def get_access(id, cursor), do: get("/pages/#{id}/access", compact(%{cursor: cursor}))

  @impl true
  def set_restriction(id, restricted),
    do: put("/pages/#{id}/access/restriction", %{restricted: restricted})

  @impl true
  def add_grants(id, grants), do: post("/pages/#{id}/access/grants", %{grants: grants})

  @impl true
  def update_grant(id, grant_id, role),
    do: patch("/pages/#{id}/access/grants/#{grant_id}", %{role: role})

  @impl true
  def remove_grant(id, grant_id) do
    case request(:delete, "/pages/#{id}/access/grants/#{grant_id}", nil, []) do
      {:ok, _} -> {:ok, %{}}
      {:error, %Error{status: 404}} -> {:ok, %{}}
      error -> error
    end
  end

  defp get(path, params \\ nil) do
    params = if params, do: compact(params), else: %{}

    if params == %{},
      do: request(:get, path, nil, []),
      else: request(:get, path, nil, params: params)
  end

  defp post(path, body), do: request(:post, path, body, [])
  defp put(path, body), do: request(:put, path, body, [])
  defp patch(path, body), do: request(:patch, path, body, [])

  defp patch_meta(_id, meta) when map_size(meta) == 0, do: {:ok, nil}

  defp patch_meta(id, meta), do: request(:patch, "/pages/#{id}", meta, [])

  defp put_content(id, attrs) do
    body =
      attrs
      |> Map.take([:content, :operation])
      |> Map.put_new(:operation, "replace")

    request(:put, "/pages/#{id}/content", body, [])
  end

  # v1 DTOs use `parentId`; older callers pass `parentPageId`.
  defp rename_parent(attrs) do
    case Map.pop(attrs, :parentPageId) do
      {nil, attrs} -> attrs
      {parent_id, attrs} -> Map.put(attrs, :parentId, parent_id)
    end
  end

  defp request(method, path, body, options) do
    options =
      Config.req_options()
      |> Keyword.merge(
        method: method,
        url: Config.api_url() <> path,
        headers: headers()
      )
      |> Keyword.merge(options)

    options = if body, do: Keyword.put(options, :json, body), else: options

    case Req.request(options) do
      {:ok, %{status: status, body: %{"error" => %{} = error}}} when map_size(error) > 0 ->
        {:error, Error.from_response(error["statusCode"] || status, %{"error" => error})}

      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, empty_to_map(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, reason} ->
        {:error, %Error{message: "Docmost request failed", details: reason}}
    end
  end

  defp headers do
    [
      {"authorization", "Bearer " <> Config.api_key()},
      {"accept", "application/json"},
      {"user-agent", "docmost-mcp/0.1.0"}
    ]
  end

  defp empty_to_map(body) when body in [nil, "", %{}], do: %{}
  defp empty_to_map(body), do: body
  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
