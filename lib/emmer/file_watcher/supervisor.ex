defmodule Emmer.FileWatcher.Supervisor do
  @moduledoc """
  DynamicSupervisor to handle the creation of FileWatcher processes using a
  `one_for_one` strategy. Each FileWatcher process is registered with a unique
  watcher_id in the registry for easy lookup and management.
  """

  use DynamicSupervisor
  require Logger

  alias Emmer.EmmerRoot

  @registry_name Emmer.FileWatcher.Registry

  @doc """
  Starts the FileWatcher supervisor.
  """
  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Finds or creates a FileWatcher process for the given folder_path.

  If a FileWatcher process already exists for this folder_path, returns {:exists, folder_path}.
  Otherwise, creates a new FileWatcher process and returns {:ok, pid}.
  """
  def find_or_create(folder_path) do
    if file_watcher_exists?(folder_path) do
      {:exists, folder_path}
    else
      case start_child(folder_path) do
        {:ok, pid} ->
          Logger.info("[FileWatcher.Supervisor] Started FileWatcher for folder_path: #{folder_path}")
          {:ok, pid}
        {:error, reason} ->
          Logger.error("[FileWatcher.Supervisor] Failed to start FileWatcher for folder_path: #{folder_path}, reason: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Determines if a FileWatcher process exists for the given folder_path.
  """
  def file_watcher_exists?(folder_path) do
    case Registry.lookup(@registry_name, folder_path) do
      [] -> false
      _ -> true
    end
  end

  @doc """
  Starts a new FileWatcher process for the given folder_path.
  """
  def start_child(folder_path) do
    child_spec = {Emmer.FileWatcher, folder_path}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stops a FileWatcher process for the given folder_path.
  """
  def stop_child(folder_path) do
    case Registry.lookup(@registry_name, folder_path) do
      [{pid, _}] ->
        # Broadcast before terminating to ensure the message is sent
        Phoenix.PubSub.broadcast(Emmer.PubSub, "watcher:#{folder_path}", {:watcher_stopped, folder_path})
        
        case DynamicSupervisor.terminate_child(__MODULE__, pid) do
          :ok ->
            Logger.info("[FileWatcher.Supervisor] Stopped FileWatcher for folder_path: #{folder_path}")
            :ok
          {:error, reason} ->
            Logger.error("[FileWatcher.Supervisor] Failed to stop FileWatcher for folder_path: #{folder_path}, reason: #{inspect(reason)}")
            {:error, reason}
        end
      [] ->
        Logger.warn("[FileWatcher.Supervisor] FileWatcher not found for folder_path: #{folder_path}")
        {:error, :not_found}
    end
  end

  @doc """
  Returns the count of FileWatcher processes managed by this supervisor.
  """
  def file_watcher_count, do: DynamicSupervisor.which_children(__MODULE__) |> length

  @doc """
  Returns a list of active folder_paths.
  """
  def active_folder_paths do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} ->
      case Registry.keys(@registry_name, pid) do
        [folder_path] -> folder_path
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Gets the PID of a specific FileWatcher process.
  """
  def get_file_watcher_pid(folder_path) do
    case Registry.lookup(@registry_name, folder_path) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Checks if a FileWatcher process is running.
  """
  def file_watcher_running?(folder_path) do
    case get_file_watcher_pid(folder_path) do
      {:ok, pid} -> Process.alive?(pid)
      {:error, :not_found} -> false
    end
  end

  @impl true
  def init(_arg) do
    Logger.info("[FileWatcher.Supervisor] Starting FileWatcher DynamicSupervisor")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
