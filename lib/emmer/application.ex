defmodule Emmer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Handoff

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      EmmerWeb.Telemetry,
      # Start the Ecto repository
      Emmer.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Emmer.PubSub},
      # Start Finch
      {Finch, name: Emmer.Finch},
      # Start the Endpoint (http/https)
      EmmerWeb.Endpoint,
      # Keep these for compatibility during transition
      # Start the build server registry (for compatibility)
      {Registry, keys: :unique, name: Emmer.Builder.ServerRegistry},
      # Start the build logger registry (for log listeners)
      {Registry, keys: :duplicate, name: Emmer.Builder.BuildRegistry},
      # Start the builder server supervisor (compatibility layer)
      Emmer.Builder.ServerSupervisor,
      # Start the record loader registry
      {Registry, keys: :unique, name: Emmer.RecordLoader.Registry},
      # Start the record loader supervisor (still used by DAG)
      Emmer.RecordLoader.Supervisor,

      # Start the file watcher registry
      {Registry, keys: :unique, name: Emmer.FileWatcher.Registry},
      # Start the file watcher supervisor
      Emmer.FileWatcher.Supervisor,

    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Emmer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if GenServer.whereis(Handoff.DistributedExecutor) == nil do
    {:ok, _pid} = Handoff.start()
    IO.puts "Handoff Application started."
  else
    IO.puts "Handoff Application already running."
  end

  # Register the local node with some default capabilities for local execution
  # This allows DistributedExecutor to find and use the current node.
  Handoff.DistributedExecutor.register_local_node(%{cpu: 2, memory: 1024, gpu: 0})
  IO.puts "Local node registered with Handoff."

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EmmerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
