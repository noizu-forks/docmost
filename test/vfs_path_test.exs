defmodule DocmostMCP.VFS.PathTest do
  use ExUnit.Case, async: true

  alias DocmostMCP.VFS.Path

  test "root parses from empty, slash, and trailing slash" do
    assert Path.parse("/") == {:ok, :root}
    assert Path.parse("") == {:ok, :root}
    assert Path.parse("/engineering/") == {:ok, {:space, "engineering"}}
  end

  test "space, page, meta, and nested page dir shapes" do
    assert Path.parse("/eng") == {:ok, {:space, "eng"}}
    assert Path.parse("/eng/start.md") == {:ok, {:page, "eng", ["start"]}}
    assert Path.parse("/eng/start.meta") == {:ok, {:meta, "eng", ["start"]}}
    assert Path.parse("/eng/a/b") == {:ok, {:page_dir, "eng", ["a", "b"]}}
    assert Path.parse("/eng/a/b/leaf.md") == {:ok, {:page, "eng", ["a", "b", "leaf"]}}
    assert Path.parse("/eng/a/b/leaf.meta") == {:ok, {:meta, "eng", ["a", "b", "leaf"]}}
  end

  test "bare extension leaves are enoent (regex rejects leading dot)" do
    assert Path.parse("/eng/.md") == {:error, :enoent}
    assert Path.parse("/eng/.meta") == {:error, :enoent}
    assert Path.parse("/eng/.hidden") == {:error, :enoent}
  end

  test "traversal and malformed segments are enoent" do
    assert Path.parse("/eng/../start.md") == {:error, :enoent}
    assert Path.parse("/eng/.") == {:error, :enoent}
    assert Path.parse("/eng/st*ff") == {:error, :enoent}
    assert Path.parse("/eng/a b") == {:error, :enoent}
    assert Path.parse(nil) == {:error, :enoent}
    assert Path.parse(42) == {:error, :enoent}
  end
end
