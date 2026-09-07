defmodule DocmostMCP.Config do
  @moduledoc false

  def client, do: Application.fetch_env!(:docmost_mcp, :client)
  def writes?, do: Application.get_env(:docmost_mcp, :writes, false)
  def req_options, do: Application.get_env(:docmost_mcp, :req_options, [])

  def api_url do
    Application.get_env(:docmost_mcp, :api_url, "https://docmost.noizu.com")
    |> case do
      url when is_binary(url) and url != "" -> url
      _ -> "https://docmost.noizu.com"
    end
    |> String.trim_trailing("/")
    |> then(&if(String.ends_with?(&1, "/api"), do: &1, else: &1 <> "/api"))
  end

  def api_key do
    case Application.get_env(:docmost_mcp, :api_key) do
      key when is_binary(key) and key != "" -> key
      _ -> raise "DOCMOST_API_KEY is required"
    end
  end
end
