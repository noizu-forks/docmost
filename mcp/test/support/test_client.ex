defmodule DocmostMCP.TestClient do
  @moduledoc false

  @behaviour DocmostMCP.ClientBehaviour
  use Agent

  def start do
    if Process.whereis(__MODULE__), do: Agent.stop(__MODULE__)
    Agent.start_link(fn -> seed() end, name: __MODULE__)
  end

  def put_share(page, shares),
    do: Agent.update(__MODULE__, &%{&1 | shares: Map.put(&1.shares, page, shares)})

  def put_permission_info(page, info),
    do: Agent.update(__MODULE__, &%{&1 | permissions: Map.put(&1.permissions, page, info)})

  def put_pages(pages), do: Agent.update(__MODULE__, &%{&1 | pages: pages})
  def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.calls))

  defp seed do
    %{
      spaces: [%{"id" => "s1", "slug" => "engineering", "name" => "Engineering"}],
      pages: [
        %{
          "id" => "p1",
          "slugId" => "start",
          "spaceId" => "s1",
          "title" => "Start",
          "content" => "# Start\n",
          "updatedAt" => "2026-01-01T00:00:00Z"
        }
      ],
      shares: %{},
      permissions: %{
        "p1" => %{
          "hasDirectRestriction" => false,
          "hasInheritedRestriction" => false,
          "canAccess" => true,
          "canEdit" => true,
          "permissions" => []
        }
      },
      calls: []
    }
  end

  def list_spaces(_cursor), do: {:ok, Agent.get(__MODULE__, & &1.spaces)}
  def get_space(id), do: fetch(:spaces, id)
  def create_space(attrs), do: {:ok, Map.put(stringify(attrs), "id", "s-new")}

  def list_pages(space, _cursor) do
    record({:list_pages, space})
    pages = Agent.get(__MODULE__, &Enum.filter(&1.pages, fn p -> p["spaceId"] == space end))
    {:ok, %{"pages" => Enum.filter(pages, &is_nil(&1["parentPageId"])), "meta" => %{}}}
  end

  def list_child_pages(page, _cursor) do
    record({:list_child_pages, page})
    pages = Agent.get(__MODULE__, &Enum.filter(&1.pages, fn p -> p["parentPageId"] == page end))
    {:ok, %{"pages" => pages, "meta" => %{}}}
  end

  def get_page(id), do: fetch(:pages, id)

  def create_page(attrs) do
    page =
      attrs
      |> stringify()
      |> Map.merge(%{
        "id" => "p-new",
        "slugId" => "new-page",
        "updatedAt" => "2026-01-02T00:00:00Z"
      })

    Agent.update(__MODULE__, &%{&1 | pages: &1.pages ++ [page]})
    {:ok, page}
  end

  def update_page(id, attrs) do
    Agent.get_and_update(__MODULE__, fn state ->
      page = Enum.find(state.pages, &(&1["id"] == id)) |> Map.merge(stringify(attrs))

      {{:ok, page},
       %{state | pages: Enum.map(state.pages, &if(&1["id"] == id, do: page, else: &1))}}
    end)
  end

  def delete_page(id) do
    Agent.update(__MODULE__, &%{&1 | pages: Enum.reject(&1.pages, fn p -> p["id"] == id end)})
    :ok
  end

  def get_share(id), do: {:ok, Agent.get(__MODULE__, &Map.get(&1.shares, id, []))}

  def create_share(attrs) do
    share = %{
      "id" => "sh1",
      "key" => "public-key",
      "level" => 0,
      "includeSubPages" => attrs[:includeSubPages],
      "searchIndexing" => attrs[:searchIndexing]
    }

    Agent.update(__MODULE__, &%{&1 | shares: Map.put(&1.shares, attrs[:pageId], [share])})
    {:ok, share}
  end

  def update_share(attrs) do
    Agent.update(__MODULE__, fn state ->
      shares =
        Map.new(state.shares, fn {page, rows} ->
          {page,
           Enum.map(rows, fn row ->
             if row["id"] == attrs[:shareId],
               do:
                 Map.merge(row, %{
                   "includeSubPages" => attrs[:includeSubPages],
                   "searchIndexing" => attrs[:searchIndexing]
                 }),
               else: row
           end)}
        end)

      %{state | shares: shares}
    end)

    {:ok, stringify(attrs)}
  end

  def delete_share(id) do
    Agent.update(
      __MODULE__,
      &%{
        &1
        | shares:
            Map.new(&1.shares, fn {page, shares} ->
              {page, Enum.reject(shares, fn s -> s["id"] == id end)}
            end)
      }
    )

    {:ok, %{}}
  end

  def permission_info(id),
    do:
      {:ok,
       Agent.get(
         __MODULE__,
         &Map.get(&1.permissions, id, %{
           "hasDirectRestriction" => false,
           "hasInheritedRestriction" => false,
           "canAccess" => true,
           "canEdit" => true,
           "permissions" => []
         })
       )}

  def list_permissions(id, _cursor) do
    permissions = Agent.get(__MODULE__, &(Map.get(&1.permissions, id, %{})["permissions"] || []))
    {:ok, %{"permissions" => permissions, "meta" => %{}}}
  end

  def restrict_page(id), do: permission_update(id, true)
  def remove_restriction(id), do: permission_update(id, false)
  def add_permission(attrs), do: record_result({:add_permission, attrs})
  def update_permission(attrs), do: record_result({:update_permission, attrs})
  def remove_permission(attrs), do: record_result({:remove_permission, attrs})

  defp permission_update(id, value) do
    Agent.update(__MODULE__, &put_in(&1, [:permissions, id, "hasDirectRestriction"], value))
    {:ok, %{}}
  end

  defp fetch(key, id) do
    case Agent.get(__MODULE__, &Enum.find(Map.fetch!(&1, key), fn row -> row["id"] == id end)) do
      nil -> {:error, %DocmostMCP.Error{status: 404, message: "not found"}}
      row -> {:ok, row}
    end
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp record(call), do: Agent.update(__MODULE__, &%{&1 | calls: [call | &1.calls]})

  defp record_result(call),
    do:
      (
        record(call)
        {:ok, %{}}
      )
end
