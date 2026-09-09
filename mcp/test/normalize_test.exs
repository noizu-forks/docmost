defmodule DocmostMCP.NormalizeTest do
  use ExUnit.Case, async: true

  alias DocmostMCP.Normalize

  test "value reads string then atom keys" do
    assert Normalize.value(%{"id" => "a"}, :id) == "a"
    assert Normalize.value(%{id: "a"}, :id) == "a"
    assert Normalize.value(%{"id" => "s", id: "a"}, :id) == "s"
    assert Normalize.value(%{}, :id) == nil
    assert Normalize.value("nope", :id) == nil
  end

  test "list extracts the data envelope" do
    assert Normalize.list(%{"data" => [%{"id" => "1"}]}) == [%{"id" => "1"}]
    assert Normalize.list([%{"id" => "1"}]) == [%{"id" => "1"}]
    assert Normalize.list(%{"data" => "not-a-list"}) == []
    assert Normalize.list(%{}) == []
    assert Normalize.list(nil) == []
  end

  test "next_cursor reads meta then top level" do
    assert Normalize.next_cursor(%{"meta" => %{"nextCursor" => "n1"}}) == "n1"
    assert Normalize.next_cursor(%{"nextCursor" => "n2"}) == "n2"
    assert Normalize.next_cursor(%{"meta" => %{}}) == nil
    assert Normalize.next_cursor(nil) == nil
  end

  test "slug falls back slugId then id" do
    assert Normalize.slug(%{"slug" => "s"}) == "s"
    assert Normalize.slug(%{"slugId" => "sid"}) == "sid"
    assert Normalize.slug(%{"id" => "i"}) == "i"
    assert Normalize.slug(%{}) == nil
  end

  test "id falls back pageId then spaceId" do
    assert Normalize.id(%{"id" => "i"}) == "i"
    assert Normalize.id(%{"pageId" => "p"}) == "p"
    assert Normalize.id(%{"spaceId" => "sp"}) == "sp"
    assert Normalize.id(%{}) == nil
  end

  test "title falls back name then Untitled" do
    assert Normalize.title(%{"title" => "T"}) == "T"
    assert Normalize.title(%{"name" => "N"}) == "N"
    assert Normalize.title(%{}) == "Untitled"
  end
end
