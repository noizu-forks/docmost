defmodule DocmostMCP.ClientBehaviour do
  @moduledoc "Boundary used by MCP tools/VFS and replaced by a fake in tests."

  @type result :: {:ok, map() | [map()]} | {:error, DocmostMCP.Error.t()}
  @callback list_spaces(String.t() | nil) :: result()
  @callback get_space(String.t()) :: result()
  @callback create_space(map()) :: result()
  @callback list_pages(String.t(), String.t() | nil) :: result()
  @callback list_child_pages(String.t(), String.t() | nil) :: result()
  @callback get_page(String.t()) :: result()
  @callback create_page(map()) :: result()
  @callback update_page(String.t(), map()) :: result()
  @callback delete_page(String.t()) :: :ok | {:error, DocmostMCP.Error.t()}
  @callback get_share(String.t()) :: result()
  @callback create_share(map()) :: result()
  @callback update_share(map()) :: result()
  @callback delete_share(String.t()) :: result()
  @callback permission_info(String.t()) :: result()
  @callback list_permissions(String.t(), String.t() | nil) :: result()
  @callback restrict_page(String.t()) :: result()
  @callback remove_restriction(String.t()) :: result()
  @callback add_permission(map()) :: result()
  @callback update_permission(map()) :: result()
  @callback remove_permission(map()) :: result()
end
