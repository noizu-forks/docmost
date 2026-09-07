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

  test "child pages use GET with query params and read the data meta envelope" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/pages/parent/children"
      assert conn.query_params["limit"] == "100"
      assert conn.method == "GET"
      Req.Test.json(conn, %{data: [%{id: "child"}], meta: %{nextCursor: "cursor-2"}})
    end)

    assert {:ok, raw} = Client.list_child_pages("parent", nil)
    assert [%{"id" => "child"}] = DocmostMCP.Normalize.list(raw)
    assert "cursor-2" == DocmostMCP.Normalize.next_cursor(raw)
  end

  test "create page posts to the space path without format or null parent" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/spaces/s/pages"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["content"] == "body"
      refute Map.has_key?(decoded, "format")
      refute Map.has_key?(decoded, "parentPageId")
      Req.Test.json(conn, %{id: "new"})
    end)

    assert {:ok, %{"id" => "new"}} =
             Client.create_page(%{spaceId: "s", content: "body", parentPageId: nil})
  end

  test "update page splits meta PATCH from content PUT" do
    Agent.start_link(fn -> [] end, name: __MODULE__)

    Req.Test.stub(__MODULE__, fn conn ->
      Agent.update(__MODULE__, fn state -> [{conn.method, conn.request_path} | state] end)

      body =
        case conn.method do
          "PATCH" ->
            {:ok, body, _conn} = Plug.Conn.read_body(conn)
            assert Jason.decode!(body) == %{"title" => "New"}
            %{id: "p1", title: "New"}

          "PUT" ->
            {:ok, body, _conn} = Plug.Conn.read_body(conn)
            assert Jason.decode!(body) == %{"content" => "body", "operation" => "replace"}
            %{id: "p1", title: "New", content: "body"}
        end

      Req.Test.json(conn, body)
    end)

    assert {:ok, %{"id" => "p1", "content" => "body"}} =
             Client.update_page("p1", %{title: "New", content: "body", operation: "replace"})

    assert Enum.sort(Agent.get(__MODULE__, & &1)) == [
             {"PATCH", "/api/v1/pages/p1"},
             {"PUT", "/api/v1/pages/p1/content"}
           ]
  end

  test "delete treats 204 as ok" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/api/v1/pages/p1"
      conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(204, "")
    end)

    assert :ok = Client.delete_page("p1")
  end

  test "missing grant delete treats 404 as ok" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{error: %{code: "grant_not_found", statusCode: 404}})
    end)

    assert {:ok, %{}} = Client.remove_grant("p1", "g-1")
    assert :ok = Client.delete_page("p1")
  end

  test "v1 error envelope maps to code and status" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        error: %{code: "page_not_found", message: "Page not found", statusCode: 404}
      })
    end)

    assert {:error, error} = Client.get_page("missing")
    assert error.status == 404
    assert error.code == "page_not_found"
    assert error.message == "Page not found"
  end

  test "share upsert PUTs shared flag" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/pages/p1/share"
      assert conn.method == "PUT"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == %{"shared" => true, "includeSubPages" => false}
      Req.Test.json(conn, %{shared: true, key: "k", level: 0, publicUrl: "https://x/s/k"})
    end)

    assert {:ok, %{"publicUrl" => "https://x/s/k"}} =
             Client.update_share("p1", %{shared: true, includeSubPages: false})
  end
end
