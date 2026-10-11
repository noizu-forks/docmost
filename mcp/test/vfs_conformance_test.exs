defmodule DocmostMCP.VFS.ConformanceTest do
  # Vendored + adapted battery: see test/support/vfs_conformance.ex for the
  # deviation notes against the upstream noizu_mcp conformance suite.
  use Noizu.MCP.VFS.Conformance,
    backend: DocmostMCP.VFS.Backend,
    seed: {DocmostMCP.VFS.ConformanceTree, :seed}
end
