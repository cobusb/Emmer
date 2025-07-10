defmodule Emmer.MixProject do
  use Mix.Project

  def project do
    [
      app: :emmer,
      version: "1.0.0",
      elixir: "~> 1.18.4",
      deps: deps()
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
      {:file_system, "~> 0.2"}
    ]
  end
end
