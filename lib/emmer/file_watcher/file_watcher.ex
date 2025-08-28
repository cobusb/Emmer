defmodule Emmer.FileWatcher do
  use GenServer
  require Logger

  alias Emmer.Builder.ServerSupervisor
  alias Emmer.Config

  @registry_name Emmer.FileWatcher.Registry

  def start_link(folder_path) do
    GenServer.start_link(__MODULE__, folder_path, name: {:via, Registry, {@registry_name, folder_path}})
  end

  def stop(folder_path) do
    case Registry.lookup(@registry_name, folder_path) do
      [{pid, _}] -> GenServer.stop(pid)
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def init(folder_path) do
    Logger.info("[FileWatcher] Initializing file watcher for folder_path: #{folder_path}")

    case Emmer.Repo.get_by(Emmer.EmmerRoot, path_to_config: folder_path) do
      nil ->
        Logger.error("[FileWatcher] Watcher not found for folder_path: #{folder_path}")
        {:stop, :watcher_not_found}

      emmer ->
        IO.inspect(emmer, label: "emmer!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")

        # Load configuration from emmer.config.yaml
        config_path = Path.join(emmer.path_to_config, "emmer.config.yaml")
        config = Config.load_config_file(config_path)
        source_config = config["builder"]["source_folder"]

        # Build relevant_dirs from all source directories in config
        relevant_dirs = [
          Path.expand(Path.join(emmer.path_to_config, source_config))
        ]

        # Verify directories exist
        case verify_directories(relevant_dirs) do
          :ok ->
            start_file_system_watcher(emmer, folder_path, relevant_dirs)
          {:error, reason} ->
            Logger.error("[FileWatcher] Directory verification failed for folder_path: #{folder_path}, reason: #{inspect(reason)}")
            {:stop, reason}
        end
    end
  end

  defp verify_directories(dirs) do
    Enum.reduce_while(dirs, :ok, fn dir, _acc ->
      if File.dir?(dir) do
        {:cont, :ok}
      else
        Logger.warn("[FileWatcher] Directory does not exist: #{dir}")
        {:halt, {:error, :directory_not_found, dir}}
      end
    end)
  end

  defp start_file_system_watcher(emmer, folder_path, relevant_dirs) do
    Logger.info("[FileWatcher] Starting FileSystem watcher for #{emmer.name}")
    Logger.info("[FileWatcher] Monitoring directories: #{inspect(relevant_dirs)}")

    case FileSystem.start_link(dirs: relevant_dirs) do
      {:ok, pid} ->
        Logger.info("[FileWatcher] FileSystem started with PID: #{inspect(pid)}")
        FileSystem.subscribe(pid)
        Logger.info("[FileWatcher] Subscribed to FileSystem events")

        Logger.info("Started file watcher for #{emmer.name} - monitoring: #{inspect(relevant_dirs)}")

        # Broadcast that FileWatcher has started
        Phoenix.PubSub.broadcast(Emmer.PubSub, "watcher:#{folder_path}", {:watcher_started, folder_path})

        # Trigger initial build
        Logger.info("[FileWatcher] Triggering initial build for #{emmer.name}")
        case ServerSupervisor.find_or_create(emmer.path_to_config) do
          {:ok, _pid} -> Emmer.Builder.Server.full_build(emmer.path_to_config)
          {:exists, _folder_path} -> Emmer.Builder.Server.full_build(emmer.path_to_config)
          {:error, reason} -> Logger.error("Failed to create build server: #{inspect(reason)}")
        end

        {:ok, %{
          folder_path: folder_path,
          emmer: emmer,
          file_system_pid: pid,
        }}

      {:error, reason} ->
        Logger.error("[FileWatcher] Failed to start FileSystem for folder_path: #{folder_path}, reason: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, state) do
    Logger.info("[FileWatcher] File event received: #{path} with events: #{inspect(events)}")

    # Refresh watcher data from database
    case Emmer.Repo.get_by(Emmer.EmmerRoot, path_to_config: state.folder_path) do
      nil ->
        Logger.error("[FileWatcher] Emmer not found in database for folder_path: #{state.folder_path}")
        {:stop, :emmer_not_found, state}

      updated_emmer ->
        case ServerSupervisor.find_or_create(updated_emmer.path_to_config) do
          {:ok, _pid} -> Emmer.Builder.Server.full_build(updated_emmer.path_to_config)
          {:exists, _folder_path} -> Emmer.Builder.Server.full_build(updated_emmer.path_to_config)
          {:error, reason} -> Logger.error("Failed to create build server: #{inspect(reason)}")
        end

        {:noreply, %{state | emmer: updated_emmer}}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, :stop}, state) do
    Logger.info("[FileWatcher] FileSystem stopped for folder_path: #{state.folder_path}")
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("[FileWatcher] Terminating file watcher for folder_path: #{state.folder_path}")

    # Broadcast that FileWatcher has stopped
    Phoenix.PubSub.broadcast(Emmer.PubSub, "watcher:#{state.folder_path}", {:watcher_stopped, state.folder_path})

    if state.file_system_pid do
      FileSystem.stop(state.file_system_pid)
    end

    :ok
  end
end
