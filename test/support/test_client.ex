defmodule DocmostMCP.TestClient do
  @moduledoc false

  @behaviour DocmostMCP.ClientBehaviour
  use Agent

  def start do
    if Process.whereis(__MODULE__), do: Agent.stop(__MODULE__)
    Agent.start_link(fn -> seed() end, name: __MODULE__)
  end

  def put_share(page, share),
    do: Agent.update(__MODULE__, &%{&1 | shares: Map.put(&1.shares, page, share)})

  def put_access(page, access),
    do: Agent.update(__MODULE__, &%{&1 | permissions: Map.put(&1.permissions, page, access)})

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
      permissions: %{"p1" => default_access()},
      calls: []
    }
  end

  defp default_access do
    %{"restriction" => "none", "canAccess" => true, "canEdit" => true, "grants" => []}
  end

  def list_spaces(_cursor),
    do: {:ok, %{"data" => Agent.get(__MODULE__, & &1.spaces), "meta" => %{}}}

  def get_space(id), do: fetch(:spaces, id)
  def create_space(attrs), do: {:ok, Map.put(stringify(attrs), "id", "s-new")}

  def list_pages(space, _cursor) do
    record({:list_pages, space})
    pages = Agent.get(__MODULE__, &Enum.filter(&1.pages, fn p -> p["spaceId"] == space end))
    {:ok, %{"data" => Enum.filter(pages, &is_nil(&1["parentPageId"])), "meta" => %{}}}
  end

  def list_child_pages(page, _cursor) do
    record({:list_child_pages, page})
    pages = Agent.get(__MODULE__, &Enum.filter(&1.pages, fn p -> p["parentPageId"] == page end))
    {:ok, %{"data" => pages, "meta" => %{}}}
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

  def get_share(id),
    do: {:ok, Agent.get(__MODULE__, &Map.get(&1.shares, id, %{"shared" => false}))}

  # v1 upsert: shared:false removes; shared:true creates/updates in place,
  # preserving the share id/key/publicUrl the server owns.
  def update_share(page_id, attrs) do
    record({:update_share, page_id, attrs})

    share =
      Agent.get_and_update(__MODULE__, fn state ->
        existing = Map.get(state.shares, page_id, %{})

        if stringify(attrs)["shared"] == false do
          {existing, %{state | shares: Map.delete(state.shares, page_id)}}
        else
          share =
            Map.merge(existing, %{
              "id" => existing["id"] || "sh1",
              "key" => existing["key"] || "public-key",
              "level" => 0,
              "shared" => true,
              "includeSubPages" => attrs[:includeSubPages] || false,
              "searchIndexing" => attrs[:searchIndexing] || false
            })

          {share, %{state | shares: Map.put(state.shares, page_id, share)}}
        end
      end)

    {:ok, share}
  end

  def get_access(id, _cursor),
    do: {:ok, Agent.get(__MODULE__, &Map.get(&1.permissions, id, default_access()))}

  def set_restriction(id, restricted) do
    Agent.update(__MODULE__, fn state ->
      access =
        Map.put(
          Map.get(state.permissions, id, default_access()),
          "restriction",
          if(restricted, do: "direct", else: "none")
        )

      %{state | permissions: Map.put(state.permissions, id, access)}
    end)

    {:ok, %{}}
  end

  def add_grants(page_id, grants) do
    record({:add_grants, page_id, grants})

    created =
      Enum.map(grants, fn grant ->
        %{
          "id" => "g-" <> String.slice(to_string(grant.principalId), 0, 8),
          "type" => to_string(grant.type),
          "principalId" => grant.principalId,
          "role" => grant.role
        }
      end)

    Agent.update(__MODULE__, fn state ->
      access = Map.get(state.permissions, page_id, default_access())
      access = Map.update!(access, "grants", &(&1 ++ created))
      %{state | permissions: Map.put(state.permissions, page_id, access)}
    end)

    {:ok, %{"data" => created, "meta" => %{}}}
  end

  def update_grant(page_id, grant_id, role) do
    record({:update_grant, page_id, grant_id, role})

    map_grants(page_id, fn grants ->
      Enum.map(grants, &if(&1["id"] == grant_id, do: Map.put(&1, "role", role), else: &1))
    end)

    {:ok, %{}}
  end

  def remove_grant(page_id, grant_id) do
    record({:remove_grant, page_id, grant_id})
    map_grants(page_id, &Enum.reject(&1, fn grant -> grant["id"] == grant_id end))
    {:ok, %{}}
  end

  defp map_grants(page_id, fun) do
    Agent.update(__MODULE__, fn state ->
      access = Map.get(state.permissions, page_id, default_access())
      access = Map.update!(access, "grants", fun)
      %{state | permissions: Map.put(state.permissions, page_id, access)}
    end)
  end

  defp fetch(key, id) do
    case Agent.get(__MODULE__, &Enum.find(Map.fetch!(&1, key), fn row -> row["id"] == id end)) do
      nil -> {:error, %DocmostMCP.Error{status: 404, message: "not found"}}
      row -> {:ok, row}
    end
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp record(call), do: Agent.update(__MODULE__, &%{&1 | calls: [call | &1.calls]})
end
