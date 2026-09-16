defmodule DocmostMCP.ErrorTest do
  use ExUnit.Case, async: true

  alias DocmostMCP.Error

  test "v1 envelope parses code, message, and statusCode" do
    error =
      Error.from_response(500, %{
        "error" => %{
          "code" => "page_not_found",
          "message" => "Page not found",
          "statusCode" => 404
        }
      })

    assert error.status == 404
    assert error.code == "page_not_found"
    assert error.message == "Page not found"

    assert error.details == %{
             "error" => %{
               "code" => "page_not_found",
               "message" => "Page not found",
               "statusCode" => 404
             }
           }
  end

  test "v1 envelope without statusCode falls back to the HTTP status" do
    error =
      Error.from_response(429, %{"error" => %{"code" => "rate_limited", "message" => "slow down"}})

    assert error.status == 429
    assert error.code == "rate_limited"
  end

  test "v1 envelope falls back to flat body fields and default message" do
    error =
      Error.from_response(502, %{"error" => %{}, "code" => "bad_gateway", "message" => "upstream"})

    assert error.status == 502
    assert error.code == "bad_gateway"
    assert error.message == "upstream"

    error = Error.from_response(500, %{"error" => %{"statusCode" => 500}})
    assert error.message == "Docmost request failed"
    assert error.code == nil
  end

  test "legacy flat body maps message and code" do
    error = Error.from_response(404, %{"code" => "ENOENT", "message" => "no page"})
    assert error.status == 404
    assert error.code == "ENOENT"
    assert error.message == "no page"
  end

  test "legacy body with error string uses it as message" do
    error = Error.from_response(500, %{"error" => "kaboom"})
    assert error.message == "kaboom"
    assert error.status == 500
  end

  test "empty body yields defaults" do
    error = Error.from_response(500, %{})
    assert error.status == 500
    assert error.message == "Docmost request failed"
  end

  test "atom keys are read as fallbacks" do
    error = Error.from_response(403, %{code: :forbidden, message: "nope"})
    assert error.code == :forbidden
    assert error.message == "nope"
  end

  test "non-map body is tolerated" do
    error = Error.from_response(500, "oops")
    assert error.status == 500
    assert error.message == "Docmost request failed"
  end
end
