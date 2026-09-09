defmodule DocmostMCP.Normalize do
  @moduledoc false

  def value(map, key) when is_map(map), do: map[to_string(key)] || map[key]
  def value(_, _), do: nil
  def list(%{"items" => items}) when is_list(items), do: items
  def list(%{"spaces" => items}) when is_list(items), do: items
  def list(%{"pages" => items}) when is_list(items), do: items
  def list(%{"permissions" => items}) when is_list(items), do: items
  def list(items) when is_list(items), do: items
  def list(_), do: []

  def next_cursor(map) when is_map(map) do
    value(value(map, :meta), :nextCursor) || value(map, :nextCursor)
  end

  def next_cursor(_), do: nil

  def slug(record) do
    value(record, :slug) || value(record, :slugId) || value(record, :id)
  end

  def id(record), do: value(record, :id) || value(record, :pageId) || value(record, :spaceId)
  def title(record), do: value(record, :title) || value(record, :name) || "Untitled"
end
