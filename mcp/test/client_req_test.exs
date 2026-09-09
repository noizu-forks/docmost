defmodule DocmostMCP.ClientReqTest do
  use ExUnit.Case, async: false

  alias DocmostMCP.Client.Req, as: Client

  setup do
    Application.put_env(:docmost_mcp, :api_url, "https://test.invalid")
    Application.put_env(:docmost_mcp, :api_key, "test-token")
    Application.put_env(:docmost_mcp, :req_options, plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      Application.delete_env(:docmost_mcp, :req_options)
      Application.put_env(:docmost_mcp, :api_url, "https://docs.example.com")
    end)
  end

  test "child sidebar request uses pageId and reads data meta envelope" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/pages/sidebar-pages"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert %{"pageId" => "parent", "limit" => 100} = Jason.decode!(body)

      Req.Test.json(conn, %{
        success: true,
        data: %{pages: [%{id: "child"}], meta: %{nextCursor: "cursor-2"}}
      })
    end)

    assert {:ok, raw} = Client.list_child_pages("parent", nil)
    assert [%{"id" => "child"}] = DocmostMCP.Normalize.list(raw)
    assert "cursor-2" == DocmostMCP.Normalize.next_cursor(raw)
  end

  test "create content has markdown format but no update operation" do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["format"] == "markdown"
      refute Map.has_key?(decoded, "operation")
      Req.Test.json(conn, %{success: true, data: %{id: "new"}})
    end)

    assert {:ok, %{"id" => "new"}} = Client.create_page(%{spaceId: "s", content: "body"})
  end
end
