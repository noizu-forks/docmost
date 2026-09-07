defmodule DocmostMCP.Server do
  @moduledoc false

  use Noizu.MCP.Server,
    name: "docmost",
    version: "0.1.0",
    instructions: """
    Work with Docmost spaces and Markdown wiki pages. The VFS root contains one
    directory per space; each page appears as `<slug>.md` with a sibling
    `<slug>.meta` YAML control file. Writing `share: public` to the meta file
    creates or updates a public share. Read the meta file afterward for `url`.
    Mutations require DOCMOST_MCP_WRITES=1.
    """

  tool(DocmostMCP.Tools.Core)
  vfs(DocmostMCP.VFS.Backend)
end
