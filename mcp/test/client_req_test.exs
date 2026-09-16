defmodule DocmostMCP.ClientReqTest do
  use ExUnit.Case, async: false

  alias DocmostMCP.Client.Req, as: Client

  setup do
    Application.put_env(:docmost_mcp, :api_url, "https://test.invalid")
    Application.put_env(:docmost_mcp, :api_key, "test-token")
    Application.put_env(:docmost_mcp, :req_options, plug: {Req.Test, __MODULE__}, retry: false)

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

  test "requests carry the bearer header and v1 base path" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert {"authorization", "Bearer test-token"} in conn.req_headers
      assert {"accept", "application/json"} in conn.req_headers
      assert conn.request_path == "/api/v1/spaces/s1"
      Req.Test.json(conn, %{id: "s1"})
    end)

    assert {:ok, %{"id" => "s1"}} = Client.get_space("s1")
  end

  test "list spaces and pages send limit query and read envelope" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.query_params["limit"] == "100"
      assert conn.request_path in ["/api/v1/spaces", "/api/v1/spaces/s1/pages"]
      Req.Test.json(conn, %{data: [%{"id" => "row"}], meta: %{nextCursor: "c2"}})
    end)

    assert {:ok, raw} = Client.list_spaces(nil)
    assert [%{"id" => "row"}] = DocmostMCP.Normalize.list(raw)
    assert "c2" == DocmostMCP.Normalize.next_cursor(raw)

    assert {:ok, _} = Client.list_pages("s1", "c1")
  end

  test "create space posts attrs" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/spaces"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == %{"name" => "New"}
      Req.Test.json(conn, %{id: "s2"})
    end)

    assert {:ok, %{"id" => "s2"}} = Client.create_space(%{name: "New"})
  end

  test "get page with nil cursor sends no query params" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/pages/p1"
      assert conn.query_params == %{}
      Req.Test.json(conn, %{id: "p1", title: "T"})
    end)

    assert {:ok, %{"id" => "p1"}} = Client.get_page("p1")
  end

  test "access reads pass cursors through and drop them when nil" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/pages/p1/access"

      case conn.query_params do
        %{"cursor" => "c9"} -> Req.Test.json(conn, %{restriction: "none", grants: []})
        _ -> Req.Test.json(conn, %{restriction: "none", grants: []})
      end
    end)

    assert {:ok, _} = Client.get_access("p1", nil)
    assert {:ok, _} = Client.get_access("p1", "c9")
  end

  test "restriction and grant mutations hit their v1 paths" do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = if body == "", do: %{}, else: Jason.decode!(body)

      case {conn.method, conn.request_path} do
        {"PUT", "/api/v1/pages/p1/access/restriction"} ->
          assert decoded == %{"restricted" => true}
          Req.Test.json(conn, %{restriction: "direct"})

        {"POST", "/api/v1/pages/p1/access/grants"} ->
          assert decoded == %{
                   "grants" => [%{"type" => "user", "principalId" => "u1", "role" => "writer"}]
                 }

          Req.Test.json(conn, %{data: [%{"id" => "g-1"}], meta: %{}})

        {"PATCH", "/api/v1/pages/p1/access/grants/g-1"} ->
          assert decoded == %{"role" => "reader"}
          Req.Test.json(conn, %{})

        other ->
          flunk("unexpected request: #{inspect(other)}")
      end
    end)

    assert {:ok, _} = Client.set_restriction("p1", true)

    assert {:ok, _} =
             Client.add_grants("p1", [%{type: "user", principalId: "u1", role: "writer"}])

    assert {:ok, %{} = _} = Client.update_grant("p1", "g-1", "reader")
  end

  test "update page with only meta patches without content PUT" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == %{"parentId" => "parent-1"}
      Req.Test.json(conn, %{id: "p1"})
    end)

    assert {:ok, %{"id" => "p1"}} = Client.update_page("p1", %{parentPageId: "parent-1"})
  end

  test "update page with empty attrs skips patch and content put" do
    Req.Test.stub(__MODULE__, fn conn ->
      flunk("no request expected, got #{conn.method} #{conn.request_path}")
    end)

    assert {:ok, nil} = Client.update_page("p1", %{})
  end

  test "delete page passes non-404 errors through" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{error: %{code: "forbidden", statusCode: 403}})
    end)

    assert {:error, %DocmostMCP.Error{status: 403}} = Client.delete_page("p1")
    assert {:error, %DocmostMCP.Error{status: 403}} = Client.remove_grant("p1", "g-1")
  end

  test "flat error body maps message through legacy parser" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(502, Jason.encode!(%{code: "boom", message: "exploded"}))
    end)

    assert {:error, error} = Client.get_page("p1")
    assert error.status == 502
    assert error.code == "boom"
    assert error.message == "exploded"
  end

  test "non-json 200 empty bodies normalize to empty map" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, "")
    end)

    assert {:ok, %{}} = Client.get_page("p1")
  end

  test "transport failures become generic request errors" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, %DocmostMCP.Error{message: "Docmost request failed", status: nil}} =
             Client.get_page("p1")
  end

  test "create page without parent posts bare attrs" do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == %{"title" => "Solo"}
      Req.Test.json(conn, %{id: "p2"})
    end)

    assert {:ok, %{"id" => "p2"}} = Client.create_page(%{spaceId: "s1", title: "Solo"})
  end
end
