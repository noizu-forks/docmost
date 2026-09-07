defmodule DocmostMCP.StubClient do
  @moduledoc false

  # Configurable client double for error-path tests: `put/1` installs a map of
  # `callback => response` where a response is the literal value to return or a
  # one-arity function of the call args tuple. Unstubbed callbacks return a
  # generic 500 error.
  @behaviour DocmostMCP.ClientBehaviour

  def put(responses),
    do:
      Application.put_env(
        :docmost_mcp,
        :stub_client,
        Map.merge(Application.get_env(:docmost_mcp, :stub_client, %{}), responses)
      )

  def clear, do: Application.delete_env(:docmost_mcp, :stub_client)

  def error(status, message \\ "stub"),
    do: {:error, %DocmostMCP.Error{status: status, message: message}}

  defp resolve(name, args) do
    case Application.get_env(:docmost_mcp, :stub_client, %{}) |> Map.get(name) do
      fun when is_function(fun, 1) -> fun.(args)
      nil -> error(500)
      response -> response
    end
  end

  for {name, arity} <- [
        list_spaces: 1,
        get_space: 1,
        create_space: 1,
        list_pages: 2,
        list_child_pages: 2,
        get_page: 1,
        create_page: 1,
        update_page: 2,
        delete_page: 1,
        get_share: 1,
        update_share: 2,
        get_access: 2,
        set_restriction: 2,
        add_grants: 2,
        update_grant: 3,
        remove_grant: 2
      ] do
    args = Macro.generate_arguments(arity, __MODULE__)

    def unquote(name)(unquote_splicing(args)),
      do: resolve(unquote(name), [unquote_splicing(args)])
  end
end
