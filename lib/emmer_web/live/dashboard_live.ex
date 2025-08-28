defmodule EmmerWeb.DashboardLive do
  use EmmerWeb, :live_view
  require Logger

  alias Emmer.EmmerContext
  alias Emmer.Builder.ServerSupervisor

        @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to EmmerRoot changes
      Phoenix.PubSub.subscribe(Emmer.PubSub, EmmerContext.topic())

      # Register for build logs and watcher status for existing emmers
      emmers = EmmerContext.list_emmer_roots()
      Enum.each(emmers, fn emmer ->
        ensure_subscribed_to_watcher(emmer.path_to_config)
        ensure_subscribed_to_builder(emmer.path_to_config)
        # Register with BuildLogger to receive log messages
        Registry.register(Emmer.Builder.BuildRegistry, {:build_listener, emmer.path_to_config}, nil)
      end)
    end

    {:ok,
      socket
      |> stream(:emmers, EmmerContext.list_emmer_roots(), dom_id: &"emmer-#{&1.id}")
      |> assign(
        new_emmer: EmmerContext.new_emmer_root_changeset() |> to_form(),
        show_add_form: false,
        show_error_modal: false,
        selected_error_emmer: nil,
        selected_emmer: nil,
        action: nil
      )
    }
  end

  # Ensure we're subscribed to all watchers
  defp ensure_subscribed_to_watcher(folder_path) do
    topic = "watcher:#{folder_path}"
    subscribed_topics = Process.get(:subscribed_topics, [])

    if topic in subscribed_topics do
      true
    else
      Phoenix.PubSub.subscribe(Emmer.PubSub, topic)
      Process.put(:subscribed_topics, [topic | subscribed_topics])
    end
  end

  # Helper function to check if FileWatcher is running
  defp watcher_running?(emmer) do
    Emmer.FileWatcher.Supervisor.file_watcher_running?(emmer.path_to_config)
  end

  # Ensure we're subscribed to builder events
  defp ensure_subscribed_to_builder(folder_path) do
    topic = "builder:#{folder_path}"
    subscribed_topics = Process.get(:subscribed_topics, [])

    if topic in subscribed_topics do
      true
    else
      Phoenix.PubSub.subscribe(Emmer.PubSub, topic)
      Process.put(:subscribed_topics, [topic | subscribed_topics])
    end
  end

  # Helper function to check if a build is running
  defp build_running?(emmer) do
    emmer.status == "building"
  end


  @impl true
  def handle_event("toggle_add_form", _params, socket) do
    {:noreply, assign(socket, show_add_form: !socket.assigns.show_add_form)}
  end

  @impl true
  def handle_event("save", %{"emmer" => %{"action" => "insert"}} = emmer_params, socket) do
    emmer_params = emmer_params["emmer_root"]

    case EmmerContext.create_emmer_root(emmer_params) do
      {:ok, emmer} ->
        {:noreply, assign(socket,
          new_emmer: EmmerContext.new_emmer_root_changeset() |> to_form(),
          show_add_form: false
        )
      |> put_flash(:info, "Watcher added successfully!")}

      {:error, changeset} ->
        Logger.error("DashboardLive: Error saving emmer: #{inspect(changeset)}")
        {:noreply, assign(socket,
          new_emmer: to_form(changeset)
        )}
    end
  end

  @impl true
  def handle_event("save", %{"emmer" => %{"action" => "edit"}} = emmer_params, socket) do
    emmer_params = emmer_params["emmer_root"]
    changeset = EmmerContext.change_emmer_root(socket.assigns.selected_emmer, emmer_params)

    case EmmerContext.update_emmer_root(socket.assigns.selected_emmer, changeset) do
      {:ok, emmer} ->
        {:noreply, assign(socket,
          new_emmer: EmmerContext.new_emmer_root_changeset() |> to_form(),
          show_add_form: false
        )
      |> put_flash(:info, "Watcher updated successfully!")}

      {:error, changeset} ->
        {:noreply, assign(socket,
          new_emmer: to_form(changeset)
        )}
    end
  end

  @impl true
  def handle_event("add_emmer", _params, socket) do
    {:noreply, assign(socket, show_add_form: true, new_emmer: EmmerContext.new_emmer_root_changeset() |> to_form(), action: :insert)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    emmer = EmmerContext.get_emmer_root!(id)
    changeset = EmmerContext.change_emmer_root(emmer, %{})
    {:noreply, assign(socket, show_add_form: true, new_emmer: to_form(changeset), action: :edit, selected_emmer: emmer)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    emmer = EmmerContext.get_emmer_root!(id)

    # Stop file watching for this watcher
    Emmer.Registry.unregister(String.to_integer(id))

    # Unsubscribe from rebuild events for this watcher
    Phoenix.PubSub.unsubscribe(Emmer.PubSub, "file_preview:#{id}")

    # Unregister from BuildLogger
    Registry.unregister(Emmer.Builder.BuildRegistry, {:build_listener, emmer.path_to_config})

    EmmerContext.delete_emmer_root(emmer)

    {:noreply, socket |> put_flash(:info, "Watcher removed successfully!")}
  end

  @impl true
  def handle_event("build", %{"id" => id}, socket) do
    emmer = EmmerContext.get_emmer_root!(id)
    # Ensure we're subscribed to build events for this emmer
    ensure_subscribed_to_builder(emmer.path_to_config)

    case ServerSupervisor.find_or_create(emmer.path_to_config) do
      {:ok, _pid} ->
        Emmer.Builder.Server.full_build(emmer.path_to_config)
        # Update the emmer with building status and refresh UI
        updated_emmer = %{emmer | status: "building"}
        {:noreply, stream_insert(socket, :emmers, updated_emmer)}
      {:exists, _folder_path} ->
        Emmer.Builder.Server.full_build(emmer.path_to_config)
        # Update the emmer with building status and refresh UI
        updated_emmer = %{emmer | status: "building"}
        {:noreply, stream_insert(socket, :emmers, updated_emmer)}
      {:error, reason} ->
        Logger.error("Failed to create build server: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_watch", %{"id" => id}, socket) do
    emmer = EmmerContext.get_emmer_root!(id)

    # Check if FileWatcher is currently running for this folder_path
    if Emmer.FileWatcher.Supervisor.file_watcher_running?(emmer.path_to_config) do
      # Stop watching
      Emmer.Registry.unregister(emmer.path_to_config)
      {:noreply, socket}
    else
      # Start watching
      Emmer.Registry.register(emmer.path_to_config)
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_error_details", %{"id" => id}, socket) do
    emmer = EmmerContext.get_emmer_root!(id)
    {:noreply, assign(socket, show_error_modal: true, selected_error_watcher: emmer)}
  end

  @impl true
  def handle_event("close_error_modal", _params, socket) do
    {:noreply, assign(socket, show_error_modal: false, selected_error_watcher: nil)}
  end

  # Tick is no longer needed since all processes broadcast their changes via PubSub

  # Handle EmmerRoot PubSub events for real-time updates
  @impl true
  def handle_info({:emmer_root_created, emmer_root}, socket) do
    # Subscribe to watcher and builder events
    ensure_subscribed_to_watcher(emmer_root.path_to_config)
    ensure_subscribed_to_builder(emmer_root.path_to_config)
    # Register with BuildLogger to receive log messages
    Registry.register(Emmer.Builder.BuildRegistry, {:build_listener, emmer_root.path_to_config}, nil)
    {:noreply, stream_insert(socket, :emmers, emmer_root, dom_id: "emmer-#{emmer_root.id}")}
  end

  @impl true
  def handle_info({:emmer_root_updated, emmer_root}, socket) do
    {:noreply, stream_insert(socket, :emmers, emmer_root)}
  end

  @impl true
  def handle_info({:emmer_root_deleted, emmer_root_id}, socket) do
    {:noreply, stream_delete(socket, :emmers, %{id: emmer_root_id})}
  end

  @impl true
  def handle_info(:emmer_roots_refresh_all, socket) do
    emmers = EmmerContext.list_emmer_roots()
    {:noreply, stream(socket, :emmers, emmers, dom_id: &"emmer-#{&1.id}")}
  end


  @impl true
  def handle_info({:build_log, build_folder, level, message, _metadata}, socket) do
    # You can handle the build logs here - perhaps update the UI, store in assigns, etc.
    # For now, just log it
    {:noreply, socket}
  end

  @impl true
  def handle_info({:watcher_started, folder_path}, socket) do
    # Find the EmmerRoot and refresh the UI to show updated button status
    case Emmer.Repo.get_by(Emmer.EmmerRoot, path_to_config: folder_path) do
      nil ->
        Logger.warn("DashboardLive: EmmerRoot not found for folder_path: #{folder_path}")
        {:noreply, socket}

      emmer ->
        # Just refresh the stream entry to trigger UI update
        {:noreply, stream_insert(socket, :emmers, emmer)}
    end
  end

  @impl true
  def handle_info({:watcher_stopped, folder_path}, socket) do

    # Find the EmmerRoot and refresh the UI to show updated button status
    case Emmer.Repo.get_by(Emmer.EmmerRoot, path_to_config: folder_path) do
      nil ->
        Logger.warn("DashboardLive: EmmerRoot not found for folder_path: #{folder_path}")
        {:noreply, socket}

      emmer ->
        # Just refresh the stream entry to trigger UI update
        {:noreply, stream_insert(socket, :emmers, emmer)}
    end
  end

  @impl true
  def handle_info({:build_started, _build_id, folder_path}, socket) do

    # Find the EmmerRoot and update status to building
    case Emmer.Repo.get_by(Emmer.EmmerRoot, path_to_config: folder_path) do
      nil ->
        Logger.warn("DashboardLive: EmmerRoot not found for folder_path: #{folder_path}")
        {:noreply, socket}

      emmer ->
        updated_emmer = %{emmer | status: "building"}
        {:noreply, stream_insert(socket, :emmers, updated_emmer)}
    end
  end

  @impl true
  def handle_info({:build_completed, _build_id, _final_state}, socket) do

    # Find all emmers and reset their status to normal
    emmers = EmmerContext.list_emmer_roots()
    updated_emmers = Enum.map(emmers, fn emmer ->
      if emmer.status == "building" do
        %{emmer | status: "completed"}
      else
        emmer
      end
    end)

    {:noreply, stream(socket, :emmers, updated_emmers, dom_id: &"emmer-#{&1.id}")}
  end

  @impl true
  def handle_info({:build_error, _build_id, _error}, socket) do

    # Find all emmers and reset their status to normal
    emmers = EmmerContext.list_emmer_roots()
    updated_emmers = Enum.map(emmers, fn emmer ->
      if emmer.status == "building" do
        %{emmer | status: "error"}
      else
        emmer
      end
    end)

    {:noreply, stream(socket, :emmers, updated_emmers, dom_id: &"emmer-#{&1.id}")}
  end

  @impl true
  def handle_info({:build_progress, build_id, progress_data}, socket) do
    # Just acknowledge the progress, no UI updates needed for now
    {:noreply, socket}
  end

  @impl true
  def handle_info(msg, socket) do
    Logger.debug("DashboardLive: Received unexpected message: #{inspect(msg)}")
    {:noreply, socket}
  end

end
