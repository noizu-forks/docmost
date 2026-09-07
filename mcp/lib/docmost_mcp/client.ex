defmodule DocmostMCP.Client do
  @moduledoc false

  def list_spaces(cursor \\ nil), do: apply(DocmostMCP.Config.client(), :list_spaces, [cursor])

  def list_pages(space_id, cursor \\ nil),
    do: apply(DocmostMCP.Config.client(), :list_pages, [space_id, cursor])

  def list_child_pages(page_id, cursor \\ nil),
    do: apply(DocmostMCP.Config.client(), :list_child_pages, [page_id, cursor])

  for {name, arity} <- [
        get_space: 1,
        create_space: 1,
        get_page: 1,
        create_page: 1,
        update_page: 2,
        delete_page: 1,
        get_share: 1,
        create_share: 1,
        update_share: 1,
        delete_share: 1,
        permission_info: 1,
        list_permissions: 2,
        restrict_page: 1,
        remove_restriction: 1,
        add_permission: 1,
        update_permission: 1,
        remove_permission: 1
      ] do
    args = Macro.generate_arguments(arity, __MODULE__)

    def unquote(name)(unquote_splicing(args)),
      do: apply(DocmostMCP.Config.client(), unquote(name), [unquote_splicing(args)])
  end
end
