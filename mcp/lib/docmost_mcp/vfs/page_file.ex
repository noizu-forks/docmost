defmodule DocmostMCP.VFS.PageFile do
  @moduledoc false
  alias DocmostMCP.Normalize

  def encode(page) do
    fields = [
      {"id", Normalize.id(page)},
      {"title", Normalize.title(page)},
      {"parent", Normalize.value(page, :parentPageId)},
      {"space", Normalize.value(page, :spaceId)},
      {"updated", Normalize.value(page, :updatedAt)}
    ]

    yaml =
      fields
      |> Enum.reject(&is_nil(elem(&1, 1)))
      |> Enum.map_join("\n", fn {key, value} -> "#{key}: #{inspect(to_string(value))}" end)
      |> Kernel.<>("\n")

    "---\n" <> yaml <> "---\n" <> (Normalize.value(page, :content) || "")
  end

  def decode(data) when is_binary(data) do
    case data do
      "---\n" <> rest ->
        case :binary.split(rest, "\n---\n") do
          [yaml, body] ->
            case YamlElixir.read_from_string(yaml) do
              {:ok, %{} = meta} -> {:ok, meta, body}
              _ -> {:error, :eio}
            end

          _ ->
            {:ok, %{}, data}
        end

      _ ->
        {:ok, %{}, data}
    end
  end
end
