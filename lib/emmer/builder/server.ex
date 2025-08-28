defmodule Emmer.Builder.Server do
  @moduledoc """
  Compatibility layer that redirects old Builder.Server calls to the new DAG system.
  This module maintains the same API as the old Builder.Server but delegates
  all work to the DAG-based build system.
  """

  alias Emmer.DAG.BuildManager
  alias Emmer.Builder.BuildLogger

  # Client API - Maintain backward compatibility

  @doc """
  Starts a new build server for the given folder path.
  Now creates a lightweight wrapper that uses the DAG system.
  """
  def start_link(_folder_path) do
    # Return a fake PID to maintain compatibility
    # The actual build will be managed by DAG.BuildManager
    {:ok, self()}
  end

  @doc """
  Starts a full build for the given folder path.
  """
  def full_build(folder_path) do
    BuildLogger.info(folder_path, "Starting full build using DAG system")
    
    # Start the build using the DAG system
    case BuildManager.start_build(folder_path) do
      {:ok, build_id} ->
        BuildLogger.info(folder_path, "DAG build started: #{build_id}")
        :ok
      {:error, reason} ->
        BuildLogger.error(folder_path, "Failed to start DAG build: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Starts a partial build for a specific subfolder.
  In the DAG system, this is handled the same as a full build
  since the DAG will determine what needs to be processed.
  """
  def partial_build(folder_path, sub_folder_path) do
    BuildLogger.info(folder_path, "Starting partial build for #{sub_folder_path} using DAG system")
    
    # For now, treat partial builds as full builds
    # The DAG system will optimize what actually needs to run
    full_build(folder_path)
  end

  @doc """
  Gets the current build progress.
  """
  def get_build_progress(_folder_path) do
    # Get progress from the DAG system
    case BuildManager.get_build_progress() do
      {:ok, progress} ->
        {:ok, progress}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stops a specific build.
  """
  def stop_build(folder_path) do
    BuildLogger.info(folder_path, "Stopping build via DAG system")
    BuildManager.stop_build()
    :ok
  end

  @doc """
  Cleans up old processes for this folder path.
  In the DAG system, this is handled automatically.
  """
  def cleanup_old_processes(folder_path) do
    # DAG system handles cleanup automatically
    BuildLogger.debug(folder_path, "Cleanup requested - handled by DAG system")
    :ok
  end
end