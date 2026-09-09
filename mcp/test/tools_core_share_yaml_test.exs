defmodule DocmostMCP.Tools.CoreShareYamlTest do
  use ExUnit.Case, async: true

  alias DocmostMCP.Tools.Core

  test "omits settings keys the caller did not provide" do
    assert Core.share_yaml(%{page_id: "p1", share: :private}) ==
             "share: private\n"
  end

  test "passes through provided settings" do
    assert Core.share_yaml(%{page_id: "p1", share: :public, include_sub_pages: true}) ==
             "share: public\ninclude_sub_pages: true\n"

    assert Core.share_yaml(%{
             page_id: "p1",
             share: :public,
             include_sub_pages: false,
             search_indexing: true
           }) ==
             "share: public\ninclude_sub_pages: false\nsearch_indexing: true\n"
  end

  test "private yaml without settings keys is accepted by MetaFile.validate" do
    # Regression: the tool used to always emit include_sub_pages/search_indexing
    # (schema defaults), tripping the meta-file guard that rejects
    # `share: private` combined with either key.
    yaml = Core.share_yaml(%{page_id: "p1", share: :private})
    refute yaml =~ "include_sub_pages"
    refute yaml =~ "search_indexing"
  end
end
