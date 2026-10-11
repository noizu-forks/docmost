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

  # ── session-identity auth (fork integration) ──────────────────────────────

  @doc "Docmost APP_SECRET — signs/verifies session JWTs. Set via DOCMOST_APP_SECRET."
  def app_secret, do: Application.get_env(:docmost_mcp, :app_secret)

  @doc "Opt-in static shared-key fallback (local/dev CLI use). Default: disabled."
  def allow_static_key? do
    Application.get_env(:docmost_mcp, :allow_static_key, false) and
      static_api_key() != nil
  end

  @doc "The static shared DOCMOST_API_KEY, when configured."
  def static_api_key do
    case Application.get_env(:docmost_mcp, :api_key) do
      key when is_binary(key) and key != "" -> key
      _ -> nil
    end
  end

  def start_http?, do: Application.get_env(:docmost_mcp, :start_http, true)

  def http_port, do: Application.get_env(:docmost_mcp, :http_port, 4000)
end
