defmodule Emmer.Config do
  @moduledoc """
  Handles loading and management of Emmer configuration from emmer.config.yaml.

  This module provides a centralized way to access all configuration settings
  for the Emmer static site generator.
  """

  require Logger

  @doc """
  Loads configuration from a specific file path.
  """
  def load_config_file(config_path) do
    try do
      config = YamlElixir.read_from_file!(config_path)
    rescue
      e ->
        Logger.error("Failed to load configuration from #{config_path}: #{inspect(e)}")
    end
  end


  @doc """
  Gets a configuration value using dot notation.

  ## Examples
      iex> get_config(config, "build.source.content")
      "content"

      iex> get_config(config, "server.port", 4000)
      4000
  """
  def get_config(config, key, default \\ nil) do
    keys = String.split(key, ".")
    Enum.reduce(keys, config, fn key, acc ->
      Map.get(acc, key)
    end)
  end

end
