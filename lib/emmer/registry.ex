defmodule Emmer.Registry do
  @moduledoc """
  Simple registry wrapper for FileWatcher processes.
  Uses the FileWatcher.Supervisor for process management.
  """

  alias Emmer.FileWatcher.Supervisor

  @doc """
  Registers a FileWatcher process for the given folder_path.
  """
  def register(folder_path) do
    case Supervisor.find_or_create(folder_path) do
      {:ok, pid} -> {:ok, pid}
      {:exists, _} -> {:error, :already_registered}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Unregisters a FileWatcher process for the given folder_path.
  """
  def unregister(folder_path) do
    Supervisor.stop_child(folder_path)
  end

  @doc """
  Lists all registered folder_paths.
  """
  def list do
    Supervisor.active_folder_paths()
  end
end
