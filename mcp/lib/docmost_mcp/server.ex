defmodule DocmostMCP.Server do
  @moduledoc false

  use Noizu.MCP.Server,
    name: "docmost",
    version: "0.1.0",
    # Per-request principal resolution (fork session-identity auth): the HTTP
    # plug verifies the docmost session JWT and its claims flow to the session
    # per request; this MFA runs in the session process right before handler
    # dispatch, recording the raw JWT for DocmostMCP.Auth.current_bearer/0.
    principal: {DocmostMCP.Auth, :principal_from_claims, []},
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
