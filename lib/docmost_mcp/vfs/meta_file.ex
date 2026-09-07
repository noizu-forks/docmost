defmodule DocmostMCP.VFS.MetaFile do
  @moduledoc false
  alias DocmostMCP.{Client, Config, Error, Normalize}
  @write ~w(share include_sub_pages search_indexing access permissions permissions_mode)
  @readonly ~w(id page_id url share_level access_level effective_share effective_access)
  @roles ~w(reader writer)
  @uuid ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/

  def read(page) do
    id = Normalize.id(page)

    with {:ok, share} <- Client.get_share(id),
         {:ok, access} <- all_access(id) do
      {:ok, canonical(page, share, access)}
    end
  end

  def apply(page, yaml) do
    with true <- Config.writes?() || {:error, :eacces},
         {:ok, %{} = raw} <- YamlElixir.read_from_string(yaml),
         doc = stringify(raw),
         :ok <- validate(doc),
         {:ok, before} <- read(page),
         :ok <- apply_share(page, doc, before),
         :ok <- apply_access(page, doc, before),
         :ok <- apply_permissions(page, doc, before),
         {:ok, after_state} <- read(page) do
      {:ok, after_state}
    else
      {:error, _} = error -> error
      _ -> {:error, :eio}
    end
  end

  def encode(meta) do
    [
      {"page_id", meta.page_id},
      {"share", meta.share},
      {"share_level", meta.share_level},
      {"url", meta.url},
      {"include_sub_pages", meta.include_sub_pages},
      {"search_indexing", meta.search_indexing},
      {"access", meta.access},
      {"access_level", meta.access_level},
      {"permissions", Enum.map(meta.permissions, &Map.delete(&1, "grant_id"))}
    ]
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{yaml(v)}" end)
    |> Kernel.<>("\n")
  end

  defp validate(doc) do
    keys = Map.keys(doc)

    cond do
      Enum.any?(keys, &(&1 in @readonly)) ->
        {:error, :erofs}

      keys -- (@write ++ @readonly) != [] ->
        {:error, :eio}

      doc["share"] not in [nil, "public", "private"] ->
        {:error, :eio}

      doc["share"] == "private" and
          (Map.has_key?(doc, "include_sub_pages") or Map.has_key?(doc, "search_indexing")) ->
        {:error, :eio}

      doc["access"] not in [nil, "open", "restricted"] ->
        {:error, :eio}

      doc["permissions_mode"] not in [nil, "add", "replace"] ->
        {:error, :eio}

      not permissions_valid?(doc["permissions"]) ->
        {:error, :eio}

      true ->
        :ok
    end
  end

  defp permissions_valid?(nil), do: true

  defp permissions_valid?(items) when is_list(items) and length(items) <= 25 do
    Enum.all?(items, fn p ->
      users = p["user_ids"] || []
      groups = p["group_ids"] || []

      p["role"] in @roles and is_list(users) and is_list(groups) and length(users) <= 25 and
        length(groups) <= 25 and (users != [] or groups != []) and (users == [] or groups == []) and
        Enum.all?(users ++ groups, &(is_binary(&1) and Regex.match?(@uuid, &1)))
    end)
  end

  defp permissions_valid?(_), do: false

  # Share is one upsert: `PUT {shared: bool, ...}` (false deletes server-side).
  defp apply_share(page, doc, before) do
    desired = doc["share"]
    settings? = Map.has_key?(doc, "include_sub_pages") or Map.has_key?(doc, "search_indexing")

    cond do
      is_nil(desired) and not settings? ->
        :ok

      is_nil(desired) and settings? and before.share == "private" ->
        {:error, :eio}

      desired == "private" and before.share == "private" ->
        :ok

      desired == "private" and before.share_level > 0 ->
        {:error, :eacces}

      desired == "private" ->
        result(Client.update_share(Normalize.id(page), %{shared: false}))

      before.share_level > 0 ->
        {:error, :eacces}

      desired in [nil, "public"] ->
        result(
          Client.update_share(Normalize.id(page), %{
            shared: true,
            includeSubPages: Map.get(doc, "include_sub_pages", before.include_sub_pages || false),
            searchIndexing: Map.get(doc, "search_indexing", before.search_indexing || false)
          })
        )
    end
  end

  defp apply_access(page, doc, before) do
    case doc["access"] do
      nil -> :ok
      "restricted" when before.access == "direct" -> :ok
      "open" when before.access == "open" -> :ok
      "open" when before.access == "inherited" -> {:error, :eacces}
      "open" -> result(Client.set_restriction(Normalize.id(page), false))
      "restricted" -> result(Client.set_restriction(Normalize.id(page), true))
    end
  end

  # Grant-id set ops against GET /access grants: adds batch through
  # POST /access/grants, role changes PATCH /access/grants/:grantId, removals
  # DELETE /access/grants/:grantId — no principal-identity diffing on delete.
  defp apply_permissions(_page, doc, _before) when not is_map_key(doc, "permissions"), do: :ok
  defp apply_permissions(_page, %{"permissions" => nil}, _before), do: :ok

  defp apply_permissions(page, doc, before) do
    page_id = Normalize.id(page)
    requested = Enum.flat_map(doc["permissions"], &principals/1)
    existing_by_principal = Map.new(before.permissions, &{{&1["type"], &1["id"]}, &1})
    requested_by_principal = Map.new(requested, &{identity(&1), &1})

    adds =
      requested
      |> Enum.reject(&Map.has_key?(existing_by_principal, identity(&1)))
      |> Enum.map(&%{type: &1["type"], principalId: &1["id"], role: &1["role"]})
      |> Enum.chunk_every(25)

    updates =
      Enum.flat_map(requested, fn requested_permission ->
        case existing_by_principal[identity(requested_permission)] do
          %{"grant_id" => grant_id, "role" => role} when role != requested_permission["role"] ->
            [{grant_id, requested_permission["role"]}]

          _ ->
            []
        end
      end)

    removes =
      if doc["permissions_mode"] == "replace",
        do:
          Enum.flat_map(before.permissions, fn grant ->
            if Map.has_key?(requested_by_principal, {grant["type"], grant["id"]}),
              do: [],
              else: [grant["grant_id"]]
          end),
        else: []

    # Add first: on partial API failure access remains a safe superset, never an empty ACL.
    with :ok <- each(adds, &Client.add_grants(page_id, &1)),
         :ok <- each(updates, fn {grant_id, role} -> Client.update_grant(page_id, grant_id, role) end),
         :ok <- each(removes, &Client.remove_grant(page_id, &1)),
         do: :ok
  end

  defp principals(p) do
    normalized = permission(p)

    Enum.map(normalized["user_ids"], fn id ->
      %{"type" => "user", "id" => id, "role" => normalized["role"]}
    end) ++
      Enum.map(normalized["group_ids"], fn id ->
        %{"type" => "group", "id" => id, "role" => normalized["role"]}
      end)
  end

  defp identity(p), do: {p["type"], p["id"]}

  defp permission(p),
    do: permission_principal(Normalize.value(p, :type), Normalize.value(p, :id), p)

  defp permission_principal("user", id, p),
    do: %{"role" => Normalize.value(p, :role), "user_ids" => [id], "group_ids" => []}

  defp permission_principal("group", id, p),
    do: %{"role" => Normalize.value(p, :role), "user_ids" => [], "group_ids" => [id]}

  defp permission_principal(_, _, p),
    do: %{
      "role" => Normalize.value(p, :role),
      "user_ids" => Normalize.value(p, :user_ids) || Normalize.value(p, :userIds) || [],
      "group_ids" => Normalize.value(p, :group_ids) || Normalize.value(p, :groupIds) || []
    }

  # GET /access grant `{id, type, principalId, role}` → canonical principal
  # entry; `grant_id` is internal (stripped from encoded YAML).
  defp grant(g),
    do: %{
      "type" => Normalize.value(g, :type) || "user",
      "id" => Normalize.value(g, :principalId),
      "role" => Normalize.value(g, :role) || "reader",
      "grant_id" => Normalize.value(g, :id)
    }

  defp each(items, fun),
    do: if(Enum.all?(items, &(result(fun.(&1)) == :ok)), do: :ok, else: {:error, :eio})

  # GET /access returns the restriction summary plus the (paginated) grants.
  defp all_access(id), do: collect_access(id, nil, [], MapSet.new())

  defp collect_access(id, cursor, grants, seen) do
    if cursor && MapSet.member?(seen, cursor) do
      {:error, :eio}
    else
      with {:ok, raw} <- Client.get_access(id, cursor) do
        page_grants = Normalize.list(Normalize.value(raw, :grants))
        grants = grants ++ page_grants
        next = Normalize.next_cursor(Normalize.value(raw, :grants) || raw)

        if next,
          do: collect_access(id, next, grants, MapSet.put(seen, next)),
          else: {:ok, Map.put(raw, "grants", grants)}
      end
    end
  end

  defp canonical(page, share_raw, access) do
    share = share_raw || %{}
    shared = Normalize.value(share, :shared) == true
    level = Normalize.value(share, :level) || 0

    restriction = Normalize.value(access, :restriction)
    direct = restriction == "direct"
    inherited = restriction == "inherited"

    %{
      page_id: Normalize.id(page),
      share: if(shared, do: "public", else: "private"),
      share_level: level,
      include_sub_pages: shared && !!Normalize.value(share, :includeSubPages),
      search_indexing: shared && !!Normalize.value(share, :searchIndexing),
      url: shared && public_url(page, share),
      access: if(direct, do: "direct", else: if(inherited, do: "inherited", else: "open")),
      access_level: if(direct, do: 0, else: if(inherited, do: 1, else: nil)),
      permissions: access |> Normalize.value(:grants) |> Normalize.list() |> Enum.map(&grant/1)
    }
  end

  # Server-computed `publicUrl` wins; fall back to local derivation only when
  # the server omits it (pre-v1 fork).
  defp public_url(page, share) do
    case Normalize.value(share, :publicUrl) do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        base = Config.api_url() |> String.replace_suffix("/api/v1", "")
        key = Normalize.value(share, :key)
        slug = Normalize.value(page, :slugId) || Normalize.id(page)
        if key, do: "#{base}/share/#{key}/p/untitled-#{slug}", else: nil
    end
  end

  defp result({:ok, _}), do: :ok
  defp result(:ok), do: :ok
  defp result({:error, %Error{status: 404}}), do: :ok
  defp result({:error, _}), do: {:error, :eio}
  defp stringify(v) when is_map(v), do: Map.new(v, fn {k, x} -> {to_string(k), stringify(x)} end)
  defp stringify(v) when is_list(v), do: Enum.map(v, &stringify/1)
  defp stringify(v), do: v
  defp yaml(v) when is_binary(v), do: inspect(v)
  defp yaml(v) when is_boolean(v) or is_number(v), do: to_string(v)
  defp yaml(v), do: Jason.encode!(v)
end
