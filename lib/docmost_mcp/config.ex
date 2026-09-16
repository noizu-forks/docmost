defmodule DocmostMCP.Config do
  @moduledoc false

  def client, do: Application.fetch_env!(:docmost_mcp, :client)
  def writes?, do: Application.get_env(:docmost_mcp, :writes, false)

  # `/etc/dev/config/writes` toggle setter. Returns `:ok` on success and
  # `{:error, :einval}` for non-boolean payloads — never raises; the VFS
  # control layer collapses any non-`:ok` verdict into `:eio`.
  def set_writes!(value) when is_boolean(value) do
    Application.put_env(:docmost_mcp, :writes, value)
    :ok
  end

  def set_writes!(_value), do: {:error, :einval}

  def req_options, do: Application.get_env(:docmost_mcp, :req_options, [])

  def api_url do
    Application.get_env(:docmost_mcp, :api_url, "https://docmost.noizu.com")
    |> case do
      url when is_binary(url) and url != "" -> url
      _ -> "https://docmost.noizu.com"
    end
    |> String.trim_trailing("/")
    |> then(&if(String.ends_with?(&1, "/api/v1"), do: &1, else: &1 <> "/api/v1"))
  end

  def api_key do
    case Application.get_env(:docmost_mcp, :api_key) do
      key when is_binary(key) and key != "" -> key
      _ -> raise "DOCMOST_API_KEY is required"
    end
  end
end
