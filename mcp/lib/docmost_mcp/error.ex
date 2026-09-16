defmodule DocmostMCP.Error do
  defexception [:message, :status, :code, :details]

  @type t :: %__MODULE__{
          message: String.t(),
          status: integer() | nil,
          code: String.t() | nil,
          details: term()
        }

  # v1 envelope: `{error: {code, message, statusCode}}`. Falls back to the
  # legacy flat shapes for non-v1 responses.
  def from_response(status, %{"error" => %{} = error} = body) when map_size(error) > 0 do
    %__MODULE__{
      status: error["statusCode"] || status,
      code: error["code"] || value(body, "code"),
      message: error["message"] || value(body, "message") || "Docmost request failed",
      details: body
    }
  end

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
