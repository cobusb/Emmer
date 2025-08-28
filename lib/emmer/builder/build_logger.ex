defmodule Emmer.Builder.BuildLogger do
  @moduledoc """
  Helper module for logging with build folder context.
  
  This module provides convenience functions for logging messages
  that should be dispatched to specific build folder watchers.
  """

  require Logger

  @doc """
  Log a debug message for a specific build folder.
  """
  def debug(build_folder, message, metadata \\ []) do
    Logger.debug(message, add_build_metadata(build_folder, metadata))
  end

  @doc """
  Log an info message for a specific build folder.
  """
  def info(build_folder, message, metadata \\ []) do
    Logger.info(message, add_build_metadata(build_folder, metadata))
  end

  @doc """
  Log a warning message for a specific build folder.
  """
  def warn(build_folder, message, metadata \\ []) do
    Logger.warn(message, add_build_metadata(build_folder, metadata))
  end

  @doc """
  Log an error message for a specific build folder.
  """
  def error(build_folder, message, metadata \\ []) do
    Logger.error(message, add_build_metadata(build_folder, metadata))
  end

  @doc """
  Configure the build logger backend.
  
  ## Options
  
    * `:level` - minimum level for logs to be dispatched
    * `:metadata_filter` - additional metadata filters
    * `:registry_name` - name of the registry (defaults to Emmer.BuildRegistry)
    * `:format` - log format string
  
  ## Example
  
      # In your application.ex
      Emmer.Builder.BuildLogger.configure(level: :info)
  """
  def configure(opts \\ []) do
    # Add the backend if not already added
    backends = Application.get_env(:logger, :backends, [])
    
    unless Emmer.BuildLoggerBackend in backends do
      :ok = Logger.add_backend(Emmer.BuildLoggerBackend)
    end
    
    # Configure the backend
    Logger.configure_backend(Emmer.BuildLoggerBackend, opts)
  end

  @doc """
  Remove the build logger backend.
  """
  def remove_backend do
    Logger.remove_backend(Emmer.BuildLoggerBackend)
  end

  defp add_build_metadata(build_folder, metadata) do
    Keyword.put(metadata, :build_folder, build_folder)
  end
end