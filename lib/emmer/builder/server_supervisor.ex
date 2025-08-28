defmodule Emmer.Builder.ServerSupervisor do
  @moduledoc """
  Compatibility supervisor for the old Builder.Server system.
  This is now a stub that redirects to the DAG system while maintaining the same API.
  """
  
  use DynamicSupervisor
  require Logger

  @registry_name Emmer.Builder.ServerRegistry

  @doc """
  Starts the supervisor.
  """
  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec find_or_create(any) :: :ignore | {:error, any} | {:ok, any} | {:ok, pid, any}
  @doc """
  Compatibility function that always returns success.
  The actual build is handled by the DAG system.
  """
  def find_or_create(_folder_path) do
    # Always return success - DAG system handles the actual build
    {:ok, self()}
  end

  @doc """
  Compatibility function - always returns true since DAG system handles builds.
  """
  def folder_exists?(_folder_path) do
    # DAG system handles this
    true
  end

  @doc """
  Creates a new build process using the DAG system.
  """
  def create_build(folder_path) do
    # Delegate to DAG system
    case Emmer.DAG.BuildManager.start_build(folder_path) do
      {:ok, _build_id} -> {:ok, self()}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the count of builds (always 0 for compatibility).
  """
  def build_id_count do
    # DAG system doesn't use this concept
    0
  end

  @doc """
  Return a list of active folders (empty for compatibility).
  """
  def active_folders do
    # DAG system handles this differently
    []
  end

  @doc """
  Return a list of build states (empty for compatibility).
  """
  def build_states do
    # DAG system handles this differently
    []
  end

  def start_child(folder_path) do
    # Redirect to DAG system
    create_build(folder_path)
  end

  @doc false
  @impl true
  def init(_arg) do
    Logger.info("Builder.ServerSupervisor (compatibility layer) started successfully")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end