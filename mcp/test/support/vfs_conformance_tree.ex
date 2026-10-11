defmodule DocmostMCP.VFS.ConformanceTree do
  @moduledoc """
  Seeds the standard conformance tree (namespaced under space `/cf`) into
  `DocmostMCP.TestClient` for the vendored VFS conformance battery.
  """

  def seed do
    {:ok, _} = DocmostMCP.TestClient.start()
    DocmostMCP.VersionStore.reset()
    Application.put_env(:docmost_mcp, :writes, true)

    DocmostMCP.TestClient.put_spaces([
      %{"id" => "s-cf", "slug" => "cf", "name" => "Conformance"}
    ])

    DocmostMCP.TestClient.put_pages([
      %{
        "id" => "ch",
        "slugId" => "hello",
        "spaceId" => "s-cf",
        "title" => "Hello",
        "content" => "hello world\n",
        "parentPageId" => nil
      },
      %{
        "id" => "cd",
        "slugId" => "docs",
        "spaceId" => "s-cf",
        "title" => "Docs",
        "content" => "docs index\n",
        "parentPageId" => nil,
        "children" => []
      },
      %{
        "id" => "ca",
        "slugId" => "a",
        "spaceId" => "s-cf",
        "title" => "A",
        "content" => "# alpha\nbeta gamma\n",
        "parentPageId" => "cd"
      },
      %{
        "id" => "cb",
        "slugId" => "b",
        "spaceId" => "s-cf",
        "title" => "B",
        "content" => "delta\n",
        "parentPageId" => "cd"
      }
    ])

    %Noizu.MCP.Ctx{}
  end
end
