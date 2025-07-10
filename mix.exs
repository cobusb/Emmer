defmodule Emmer.MixProject do
  use Mix.Project

  def project do
    [
      app: :emmer,
      version: "1.0.0",
      elixir: "~> 1.18.4",
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def deps do
    [
      {:solid, "~> 1.0"},
      {:yaml_elixir, "~> 2.9"},
      {:file_system, "~> 1.1.0"},
      {:excoveralls, "~> 0.18.5", only: [:test, :dev]}
    ]
  end
end
