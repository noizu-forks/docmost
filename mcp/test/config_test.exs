defmodule DocmostMCP.ConfigTest do
  use ExUnit.Case, async: false

  setup do
    saved = %{
      api_url: Application.get_env(:docmost_mcp, :api_url),
      api_key: Application.get_env(:docmost_mcp, :api_key),
      writes: Application.get_env(:docmost_mcp, :writes),
      req_options: Application.get_env(:docmost_mcp, :req_options),
      client: Application.get_env(:docmost_mcp, :client)
    }

    on_exit(fn ->
      Application.put_env(:docmost_mcp, :api_url, saved.api_url)
      Application.put_env(:docmost_mcp, :api_key, saved.api_key)
      Application.put_env(:docmost_mcp, :writes, saved.writes)
      Application.put_env(:docmost_mcp, :req_options, saved.req_options)
      Application.put_env(:docmost_mcp, :client, saved.client)
    end)

    :ok
  end

  test "api_url appends /api/v1 and strips trailing slash" do
    Application.put_env(:docmost_mcp, :api_url, "https://docs.example.com/")
    assert DocmostMCP.Config.api_url() == "https://docs.example.com/api/v1"
  end

  test "api_url keeps an explicit /api/v1 base" do
    Application.put_env(:docmost_mcp, :api_url, "https://docs.example.com/api/v1/")
    assert DocmostMCP.Config.api_url() == "https://docs.example.com/api/v1"
  end

  test "api_url falls back to the default host when unset or blank" do
    Application.delete_env(:docmost_mcp, :api_url)
    assert DocmostMCP.Config.api_url() == "https://docmost.noizu.com/api/v1"
    Application.put_env(:docmost_mcp, :api_url, "")
    assert DocmostMCP.Config.api_url() == "https://docmost.noizu.com/api/v1"
  end

  test "api_key returns a present key" do
    Application.put_env(:docmost_mcp, :api_key, "tok")
    assert DocmostMCP.Config.api_key() == "tok"
  end

  test "api_key raises when missing or blank" do
    Application.delete_env(:docmost_mcp, :api_key)

    assert_raise RuntimeError, "DOCMOST_API_KEY is required", fn ->
      DocmostMCP.Config.api_key()
    end

    Application.put_env(:docmost_mcp, :api_key, "")

    assert_raise RuntimeError, "DOCMOST_API_KEY is required", fn ->
      DocmostMCP.Config.api_key()
    end
  end

  test "writes? and req_options read application env" do
    Application.put_env(:docmost_mcp, :writes, true)
    assert DocmostMCP.Config.writes?() == true
    Application.put_env(:docmost_mcp, :writes, false)
    assert DocmostMCP.Config.writes?() == false
    Application.delete_env(:docmost_mcp, :writes)
    assert DocmostMCP.Config.writes?() == false

    Application.delete_env(:docmost_mcp, :req_options)
    assert DocmostMCP.Config.req_options() == []
    Application.put_env(:docmost_mcp, :req_options, plug: :x)
    assert DocmostMCP.Config.req_options() == [plug: :x]
  end

  test "client fetches required env" do
    Application.put_env(:docmost_mcp, :client, DocmostMCP.TestClient)
    assert DocmostMCP.Config.client() == DocmostMCP.TestClient
    Application.delete_env(:docmost_mcp, :client)
    assert_raise ArgumentError, fn -> DocmostMCP.Config.client() end
  end
end
