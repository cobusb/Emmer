defmodule EmmerWeb.PreviewChannel do
  use EmmerWeb, :channel
  require Logger

  @impl true
  def join("preview:" <> emmer_id, %{"path_to_config" => path_to_config}, socket) do
    Logger.info("Preview channel join attempt for emmer #{emmer_id} with path #{path_to_config}")

    # Verify the emmer exists and get its details
    emmer = Emmer.Repo.get(Emmer.EmmerRoot, emmer_id)

    if is_nil(emmer) do
      Logger.error("Preview channel join failed: Emmer not found for ID #{emmer_id}")
      {:error, %{reason: "Emmer not found"}}
    else
      # Subscribe to build completion events for this emmer
      Phoenix.PubSub.subscribe(Emmer.PubSub, "build_completion:#{path_to_config}")

      # Also subscribe to general builder events for progress updates
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{path_to_config}")

      Logger.info("Preview channel joined for emmer #{emmer_id} with path #{path_to_config}")

      socket = assign(socket, :emmer_id, emmer_id)
      socket = assign(socket, :path_to_config, path_to_config)

      {:ok, %{emmer_id: emmer_id, path_to_config: path_to_config}, socket}
    end
  end

  @impl true
  def join("preview:" <> emmer_id, params, socket) do
    Logger.error("Preview channel join failed: Missing path_to_config parameter. Received params: #{inspect(params)}")
    {:error, %{reason: "Missing path_to_config parameter"}}
  end

    @impl true
  def handle_info({:build_completed, build_id, final_state}, socket) do
    path_to_config = Map.get(socket.assigns, :path_to_config, "unknown")
    Logger.info("Preview channel: Build completed for #{path_to_config}")

    # Send build completion event to the client
    push(socket, "build_completed", %{
      build_id: build_id,
      status: final_state.status,
      errors: final_state.errors,
      warnings: final_state.warnings
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:build_started, build_id, folder_path}, socket) do
    Logger.info("Preview channel: Build started for #{folder_path}")

    # Send build started event to the client
    push(socket, "build_started", %{
      build_id: build_id,
      folder_path: folder_path
    })

    {:noreply, socket}
  end

    @impl true
  def handle_info({:build_progress, build_id, progress_data}, socket) do
    path_to_config = Map.get(socket.assigns, :path_to_config, "unknown")
    Logger.debug("Preview channel: Build progress for #{path_to_config}")

    # Send build progress event to the client
    push(socket, "build_progress", %{
      build_id: build_id,
      type: progress_data.type,
      data: progress_data
    })

    {:noreply, socket}
  end

    @impl true
  def handle_info({:build_error, build_id, error}, socket) do
    path_to_config = Map.get(socket.assigns, :path_to_config, "unknown")
    Logger.error("Preview channel: Build error for #{path_to_config}")

    # Send build error event to the client
    push(socket, "build_error", %{
      build_id: build_id,
      error: error
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{message: "pong"}}, socket}
  end

    @impl true
  def handle_in("refresh", _payload, socket) do
    path_to_config = Map.get(socket.assigns, :path_to_config)

    if is_nil(path_to_config) do
      Logger.error("Preview channel: Cannot trigger build - path_to_config not found in assigns")
      {:reply, {:error, %{message: "Channel not properly initialized"}}, socket}
    else
      Logger.info("Preview channel: Manual refresh requested for #{path_to_config}")

      # Trigger a build for this emmer
      case Emmer.Builder.ServerSupervisor.find_or_create(path_to_config) do
        {:ok, _pid} ->
          Emmer.Builder.Server.full_build(path_to_config)
          {:reply, {:ok, %{message: "Build triggered"}}, socket}
        {:exists, _folder_path} ->
          Emmer.Builder.Server.full_build(path_to_config)
          {:reply, {:ok, %{message: "Build triggered"}}, socket}
        {:error, reason} ->
          Logger.error("Failed to trigger build: #{inspect(reason)}")
          {:reply, {:error, %{message: "Failed to trigger build"}}, socket}
      end
    end
  end

  @impl true
  def terminate(reason, socket) do
    path_to_config = Map.get(socket.assigns, :path_to_config, "unknown")
    Logger.info("Preview channel terminated for #{path_to_config}: #{inspect(reason)}")
    :ok
  end
end
