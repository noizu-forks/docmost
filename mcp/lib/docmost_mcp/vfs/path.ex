defmodule DocmostMCP.VFS.Path do
  @moduledoc false
  @segment ~r/^[A-Za-z0-9][A-Za-z0-9._-]*$/

  def parse(path) when is_binary(path) do
    parts = path |> String.trim_trailing("/") |> String.split("/", trim: true)

    cond do
      Enum.any?(parts, &(&1 in [".", ".."])) -> {:error, :enoent}
      Enum.any?(parts, &(not Regex.match?(@segment, &1))) -> {:error, :enoent}
      parts == [] -> {:ok, :root}
      length(parts) == 1 -> {:ok, {:space, hd(parts)}}
      true -> classify(parts)
    end
  end

  def parse(_), do: {:error, :enoent}

  defp classify([space | rest]) do
    leaf = List.last(rest)
    ancestors = Enum.drop(rest, -1)

    cond do
      String.ends_with?(leaf, ".md") and leaf != ".md" ->
        {:ok, {:page, space, ancestors ++ [String.trim_trailing(leaf, ".md")]}}

      String.ends_with?(leaf, ".meta") and leaf != ".meta" ->
        {:ok, {:meta, space, ancestors ++ [String.trim_trailing(leaf, ".meta")]}}

      true ->
        {:ok, {:page_dir, space, rest}}
    end
  end
end
