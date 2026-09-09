defmodule DocmostMCP.Error do
  defexception [:message, :status, :code, :details]

  @type t :: %__MODULE__{
          message: String.t(),
          status: integer() | nil,
          code: String.t() | nil,
          details: term()
        }

  def from_response(status, body) do
    %__MODULE__{
      status: status,
      code: value(body, "code"),
      message: value(body, "message") || value(body, "error") || "Docmost request failed",
      details: body
    }
  end

  defp value(map, key) when is_map(map), do: map[key] || map[String.to_atom(key)]
  defp value(_, _), do: nil
end
