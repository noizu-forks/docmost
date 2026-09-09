defmodule DocmostMCP.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :docmost_mcp,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      test_coverage: [
        summary: [threshold: 85],
        ignore_modules: [DocmostMCP.TestClient, DocmostMCP.StubClient]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger, :ssl], mod: {DocmostMCP.Application, []}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      noizu_mcp_dep(),
      {:req, "~> 0.5"},
      {:plug, "~> 1.16", only: :test},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.11"}
    ]
  end

  # Supports both the normal checkout and the mandated nested worktree layout.
  defp noizu_mcp_dep do
    path =
      System.get_env("NOIZU_MCP_PATH") ||
        Enum.find(
          ["../../../Libs/ai/elixir-mcp", "../../../../../../Libs/ai/elixir-mcp"],
          &File.dir?(Path.expand(&1, __DIR__))
        )

    if path, do: {:noizu_mcp, path: path}, else: {:noizu_mcp, "~> 0.4.0"}
  end
end
