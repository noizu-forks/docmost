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
  # The fork base has no core /shares/create|update|delete endpoints; the v1
  # share upsert (PUT /v1/pages/:id/share, `shared: false` deletes) is the
  # write surface.
  @impl true
  def create_share(%{pageId: page_id} = attrs), do: put_share(page_id, true, attrs)

  @impl true
  def update_share(%{pageId: page_id} = attrs), do: put_share(page_id, true, attrs)

  # Callers pass the page id — v1 has no share-id-addressed delete.
  @impl true
  def delete_share(page_id), do: put_share(page_id, false, %{})

  defp put_share(page_id, shared, attrs) do
    body =
      %{
        "shared" => shared,
        "includeSubPages" => value_of(attrs, :includeSubPages, "includeSubPages"),
        "searchIndexing" => value_of(attrs, :searchIndexing, "searchIndexing")
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    request(:put, "/v1/pages/#{page_id}/share", body)
  end

  defp value_of(map, k1, k2), do: Map.get(map, k1) || Map.get(map, k2)
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
    qs = if cursor in [nil, ""], do: "", else: "?cursor=#{URI.encode_www_form(cursor)}"

    case request(:get, "/v1/pages/#{id}/access#{qs}", nil) do
      {:ok, %{"grants" => grants}} ->
        rows =
          grants
          |> unwrap()
          |> case do
            rows when is_list(rows) ->
              Enum.map(rows, fn row ->
                row
                |> Map.put("grantId", row["id"])
                |> Map.put("id", row["principalId"])
              end)

            _ ->
              []
          end

        {:ok, %{"data" => rows, "meta" => %{"nextCursor" => nil}}}

      {:ok, _} ->
        {:ok, %{"data" => [], "meta" => %{"nextCursor" => nil}}}

      error ->
        error
    end
  end

  @impl true
  def restrict_page(id),
    do: request(:put, "/v1/pages/#{id}/access/restriction", %{"restricted" => true})

  @impl true
  def remove_restriction(id),
    do: request(:put, "/v1/pages/#{id}/access/restriction", %{"restricted" => false})

  @impl true
  def add_permission(%{pageId: page_id, role: role} = attrs) do
    grants =
      grant_principals(attrs)
      |> Enum.map(fn type -> %{"type" => type, "principalId" => grant_principal_id(attrs, type), "role" => role} end)

    case grants do
      [] -> {:ok, %{}}
      grants -> request(:post, "/v1/pages/#{page_id}/access/grants", %{"grants" => grants})
    end
  end

  @impl true
  def update_permission(%{pageId: page_id, role: role} = attrs) do
    case find_grant(page_id, attrs) do
      {:ok, grant} ->
        request(:patch, "/v1/pages/#{page_id}/access/grants/#{grant["grantId"]}", %{"role" => role})

      other ->
        other
    end
  end

  @impl true
  def remove_permission(%{pageId: page_id} = attrs) do
    case find_grant(page_id, attrs) do
      {:ok, grant} ->
        request(:delete, "/v1/pages/#{page_id}/access/grants/#{grant["grantId"]}", nil)

      other ->
        other
    end
  end

  defp grant_principals(attrs) do
    user_ids = value_of(attrs, :userIds, "userIds") || []
    group_ids = value_of(attrs, :groupIds, "groupIds") || []

    Enum.map(user_ids, fn _ -> "user" end) ++ Enum.map(group_ids, fn _ -> "group" end)
  end

  defp grant_principal_id(attrs, "user"), do: (value_of(attrs, :userIds, "userIds") || []) |> List.first()
  defp grant_principal_id(attrs, "group"), do: (value_of(attrs, :groupIds, "groupIds") || []) |> List.first()

  defp find_grant(page_id, attrs) do
    case list_permissions(page_id, nil) do
      {:ok, grants} ->
        rows = Normalize.list(grants)

        principal_type = (value_of(attrs, :userIds, "userIds") && "user") || "group"

        grant =
          Enum.find(rows, fn row ->
            Normalize.value(row, :type) == principal_type and
              Normalize.value(row, :principalId) == grant_principal_id(attrs, principal_type)
          end)

        if grant, do: {:ok, grant}, else: {:ok, nil}

      error ->
        error
    end
  end

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
