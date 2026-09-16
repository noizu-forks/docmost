defmodule DocmostMCP.VFS.Controlled do
  @moduledoc """
  Docmost's VFS with the `/etc/dev` control tree composed on top.

  Delegates every non-control path to `DocmostMCP.VFS.Backend`; `/etc/dev/**`
  serves runtime introspection plus the `writes` config toggle (the same
  `DOCMOST_MCP_WRITES` flag, mutable at runtime via the mount). This is the
  single backend the server registers — composition is by delegation, and the
  first `vfs/1` registration wins.
  """

  use Noizu.MCP.VFS.Control,
    server: DocmostMCP.Server,
    real: DocmostMCP.VFS.Backend,
    toggles: [
      %{
        name: "writes",
        get: {DocmostMCP.Config, :writes?, []},
        set: {DocmostMCP.Config, :set_writes!, []}
      }
    ]
end
