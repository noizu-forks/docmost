defmodule DocmostMCP.ServerTest do
  use ExUnit.Case, async: false

  alias DocmostMCP.Server
  alias DocmostMCP.TestClient
  alias Noizu.MCP.Ctx

  setup do
    {:ok, _} = TestClient.start()
    %{ctx: %Ctx{}}
  end

  test "server_info exposes name and version" do
    info = Server.server_info()
    assert info.name == "docmost"
    assert info.version == "0.1.0"
  end

  test "__mcp__ accessors describe the registered surface" do
    assert Server.__mcp__(:tools) == [{DocmostMCP.Tools.Core, []}]
    assert Server.__mcp__(:resources) == []
    assert Server.__mcp__(:resource_templates) == []
    assert Server.__mcp__(:prompts) == []
    assert Server.__mcp__(:instructions) =~ "share: public"
    assert Server.__mcp__(:vfs) == [{DocmostMCP.VFS.Backend, []}]
    assert Server.__mcp__(:capabilities) != nil
    assert Server.__mcp__(:opts)[:name] == "docmost"
  end

  test "handle_list_tools lists the toolkit", %{ctx: ctx} do
    assert {:ok, tools, _cursor} = Server.handle_list_tools(nil, ctx)
    names = Enum.map(tools, & &1.name)
    assert "docmost_spaces_list" in names
    assert "docmost_page_share" in names
  end

  test "handle_call_tool dispatches to the toolkit", %{ctx: ctx} do
    assert %Noizu.MCP.Types.ToolResult{
             is_error: false,
             structured: %{spaces: [%{"slug" => "engineering"}]}
           } =
             Server.handle_call_tool("docmost_spaces_list", %{}, ctx)
  end

  test "handle_call_tool validates required input", %{ctx: ctx} do
    assert %Noizu.MCP.Types.ToolResult{is_error: true} =
             Server.handle_call_tool("docmost_pages_list", %{}, ctx)
  end

  test "handle_call_tool rejects unknown tools", %{ctx: ctx} do
    assert {:error, %Noizu.MCP.Error{code: -32602}} =
             Server.handle_call_tool("docmost_nope", %{}, ctx)
  end
end
