defmodule DocmostMCP.VFS.MetaFile do
  @moduledoc false
  alias DocmostMCP.{Client, Config, Error, Normalize}
  @write ~w(share include_sub_pages search_indexing access permissions permissions_mode)
  @readonly ~w(id page_id url share_id share_level access_level effective_share effective_access)
  @roles ~w(reader writer)
  @uuid ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/

  def read(page) do
    id = Normalize.id(page)

    with {:ok, share} <- Client.get_share(id),
         {:ok, info} <- Client.permission_info(id),
         {:ok, permissions} <- all_permissions(id),
         do: {:ok, canonical(page, share, info, permissions)}
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
      {"share_id", meta.share_id},
      {"url", meta.url},
      {"include_sub_pages", meta.include_sub_pages},
      {"search_indexing", meta.search_indexing},
      {"access", meta.access},
      {"access_level", meta.access_level},
      {"permissions", meta.permissions}
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
        # v1 share delete is page-addressed (shared: false)
        result(Client.delete_share(Normalize.id(page)))

      desired == "public" and before.share == "private" ->
        result(
          Client.create_share(%{
            pageId: Normalize.id(page),
            includeSubPages: Map.get(doc, "include_sub_pages", false),
            searchIndexing: Map.get(doc, "search_indexing", false)
          })
        )

      before.share_level > 0 ->
        {:error, :eacces}

      desired in [nil, "public"] ->
        result(
          Client.update_share(%{
            # v1 share upsert is page-addressed; share_id no longer suffices
            pageId: Normalize.id(page),
            shareId: before.share_id,
            includeSubPages: Map.get(doc, "include_sub_pages", before.include_sub_pages),
            searchIndexing: Map.get(doc, "search_indexing", before.search_indexing)
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
      "open" -> result(Client.remove_restriction(Normalize.id(page)))
      "restricted" -> result(Client.restrict_page(Normalize.id(page)))
    end
  end

  defp apply_permissions(_page, doc, _before) when not is_map_key(doc, "permissions"), do: :ok
  defp apply_permissions(_page, %{"permissions" => nil}, _before), do: :ok

  defp apply_permissions(page, doc, before) do
    requested = Enum.flat_map(doc["permissions"], &principals/1)
    existing = Enum.flat_map(before.permissions, &principals/1)
    existing_by_id = Map.new(existing, &{identity(&1), &1})
    requested_by_id = Map.new(requested, &{identity(&1), &1})

    adds = Enum.reject(requested, &Map.has_key?(existing_by_id, identity(&1)))

    updates =
      Enum.filter(requested, fn requested_permission ->
        case existing_by_id[identity(requested_permission)] do
          nil -> false
          existing_permission -> existing_permission["role"] != requested_permission["role"]
        end
      end)

    removes =
      if doc["permissions_mode"] == "replace",
        do: Enum.reject(existing, &Map.has_key?(requested_by_id, identity(&1))),
        else: []

    # Add first: on partial API failure access remains a safe superset, never an empty ACL.
    with :ok <- each(adds, &Client.add_permission(payload(page, &1))),
         :ok <- each(updates, &Client.update_permission(update_payload(page, &1))),
         :ok <- each(removes, &Client.remove_permission(remove_payload(page, &1))),
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

  defp payload(page, p),
    do:
      %{pageId: Normalize.id(page), role: p["role"]}
      |> principal_payload(p)

  defp remove_payload(page, p),
    do:
      %{pageId: Normalize.id(page)}
      |> principal_payload(p)

  defp update_payload(page, %{"type" => "user", "id" => id, "role" => role}),
    do: %{pageId: Normalize.id(page), userId: id, role: role}

  defp update_payload(page, %{"type" => "group", "id" => id, "role" => role}),
    do: %{pageId: Normalize.id(page), groupId: id, role: role}

  defp principal_payload(payload, %{"type" => "user", "id" => id}),
    do: Map.put(payload, :userIds, [id])

  defp principal_payload(payload, %{"type" => "group", "id" => id}),
    do: Map.put(payload, :groupIds, [id])

  defp each(items, fun),
    do: if(Enum.all?(items, &(result(fun.(&1)) == :ok)), do: :ok, else: {:error, :eio})

  defp canonical(page, share_raw, info, permissions) do
    share = effective(share_items(share_raw))

    direct = Normalize.value(info, :hasDirectRestriction) == true
    inherited = Normalize.value(info, :hasInheritedRestriction) == true
    access = if(direct, do: "direct", else: if(inherited, do: "inherited", else: "open"))

    %{
      page_id: Normalize.id(page),
      share: if(share.item, do: "public", else: "private"),
      share_level: share.level,
      share_id: share.item && Normalize.id(share.item),
      include_sub_pages: share.item && !!Normalize.value(share.item, :includeSubPages),
      search_indexing: share.item && !!Normalize.value(share.item, :searchIndexing),
      url: share.item && public_url(page, share.item),
      access: access,
      access_level: if(direct, do: 0, else: if(inherited, do: 1, else: nil)),
      permissions: Enum.map(permissions, &permission/1)
    }
  end

  defp all_permissions(id), do: collect(id, nil, [], MapSet.new())

  defp collect(id, cursor, acc, seen) do
    if cursor && MapSet.member?(seen, cursor),
      do: {:error, :eio},
      else: collect_page(id, cursor, acc, seen)
  end

  defp collect_page(id, cursor, acc, seen) do
    with {:ok, raw} <- Client.list_permissions(id, cursor) do
      rows = Normalize.list(raw)
      next = Normalize.next_cursor(raw)

      if next,
        do: collect(id, next, acc ++ rows, MapSet.put(seen, next)),
        else: {:ok, acc ++ rows}
    end
  end

  defp effective(items) do
    item = Enum.min_by(items, &(Normalize.value(&1, :level) || 0), fn -> nil end)
    %{item: item, level: item && (Normalize.value(item, :level) || 0)}
  end

  defp share_items(v) when is_list(v), do: v
  defp share_items(%{"shares" => v}) when is_list(v), do: v
  defp share_items(%{} = v) when map_size(v) > 0, do: [v]
  defp share_items(_), do: []

  defp public_url(page, share) do
    base = Config.api_url() |> String.replace_suffix("/api", "")
    key = Normalize.value(share, :key)
    slug = Normalize.value(page, :slugId) || Normalize.id(page)
    if key, do: "#{base}/share/#{key}/p/untitled-#{slug}", else: nil
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
