defmodule Emmer.FileWatcher.Registry do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register(watcher_id) do
    GenServer.call(__MODULE__, {:register, watcher_id})
  end

  def unregister(watcher_id) do
    GenServer.call(__MODULE__, {:unregister, watcher_id})
  end

  def list do
    GenServer.call(__MODULE__, :list)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, watcher_id}, _from, state) do
    case Map.get(state, watcher_id) do
      nil ->
        # Start new file watcher using the supervisor
        case Emmer.FileWatcher.Supervisor.start_file_watcher(watcher_id) do
          {:ok, pid} ->
            Logger.info("[Registry] Registered FileWatcher for watcher_id: #{watcher_id}")
            {:reply, {:ok, pid}, Map.put(state, watcher_id, pid)}
          {:error, reason} ->
            Logger.error("[Registry] Failed to register FileWatcher for watcher_id: #{watcher_id}, reason: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
      _pid ->
        Logger.warn("[Registry] FileWatcher already registered for watcher_id: #{watcher_id}")
        {:reply, {:error, :already_registered}, state}
    end
  end

  @impl true
  def handle_call({:unregister, watcher_id}, _from, state) do
    case Map.get(state, watcher_id) do
      nil ->
        Logger.warn("[Registry] FileWatcher not found for watcher_id: #{watcher_id}")
        {:reply, {:error, :not_found}, state}
      _pid ->
        # Stop file watcher using the supervisor
        case Emmer.FileWatcher.Supervisor.stop_file_watcher(watcher_id) do
          :ok ->
            Logger.info("[Registry] Unregistered FileWatcher for watcher_id: #{watcher_id}")
            {:reply, :ok, Map.delete(state, watcher_id)}
          {:error, reason} ->
            Logger.error("[Registry] Failed to unregister FileWatcher for watcher_id: #{watcher_id}, reason: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.keys(state), state}
  end
end
