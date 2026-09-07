defmodule DocmostMCP.PageFileTest do
  use ExUnit.Case, async: true

  alias DocmostMCP.VFS.PageFile

  test "encode renders frontmatter and body" do
    page = %{
      "id" => "p1",
      "title" => "Start",
      "parentPageId" => nil,
      "spaceId" => "s1",
      "updatedAt" => "2026-01-01T00:00:00Z",
      "content" => "# Start\n"
    }

    encoded = PageFile.encode(page)

    assert encoded ==
             ~s(---
id: "p1"
title: "Start"
space: "s1"
updated: "2026-01-01T00:00:00Z"
---
# Start
)
  end

  test "encode tolerates missing fields and blank content" do
    assert PageFile.encode(%{}) == "---\ntitle: \"Untitled\"\n---\n"

    assert PageFile.encode(%{"id" => "p1", "content" => nil}) ==
             "---\nid: \"p1\"\ntitle: \"Untitled\"\n---\n"
  end

  test "decode splits frontmatter from body" do
    assert {:ok, %{"title" => "T"}, "body"} = PageFile.decode("---\ntitle: T\n---\nbody")
  end

  test "decode without frontmatter returns raw body and empty meta" do
    assert {:ok, %{}, "plain"} = PageFile.decode("plain")
    assert {:ok, %{}, "---\nno closing"} = PageFile.decode("---\nno closing")
  end

  test "decode with invalid yaml is eio" do
    assert {:error, :eio} = PageFile.decode("---\n[unclosed\n---\nbody")
  end
end
