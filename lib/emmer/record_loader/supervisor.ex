defmodule Emmer.RecordLoader.Supervisor do
  @moduledoc """
  DynamicSupervisor to handle the creation of record loader agents using a
  `one_for_one` strategy. Each agent is registered with a unique name in the
  registry for easy lookup and management.
  
  This supervisor provides:
  
  * Dynamic loading of record loader modules
  * Validation of loader implementations
  * Registry-based agent tracking
  * Graceful error handling
  """

  use DynamicSupervisor
  
  alias Emmer.Builder.BuildLogger
  alias Emmer.RecordLoader.Registry, as: LoaderRegistry

  @registry_name Emmer.RecordLoader.Registry

  @doc """
  Starts the RecordLoader supervisor.
  """
  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Finds or creates a record loader agent with the given name and configuration.

  If an agent already exists for this name, returns {:exists, name}.
  Otherwise, creates a new agent and returns {:ok, pid}.
  
  ## Parameters
  
  * `name` - Unique name for the agent
  * `loader_module` - Module name (string) implementing RecordLoader.Behaviour
  * `source_config` - Configuration map for the loader
  
  ## Returns
  
  * `{:ok, pid}` - Successfully created agent
  * `{:exists, name}` - Agent already exists
  * `{:error, reason}` - Failed to create agent
  """
  def find_or_create(name, loader_module, source_config) do
    if agent_exists?(name) do
      {:exists, name}
    else
      case start_child(name, loader_module, source_config) do
        {:ok, pid} ->
          BuildLogger.info(".", "RecordLoader.Supervisor: Started agent: #{name}")
          {:ok, pid}
        {:error, reason} ->
          BuildLogger.error(".", "RecordLoader.Supervisor: Failed to start agent: #{name}, reason: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Determines if a record loader agent exists for the given name.
  """
  def agent_exists?(name) do
    case Registry.lookup(@registry_name, name) do
      [] -> false
      _ -> true
    end
  end

  @doc """
  Starts a new record loader agent with the given name and configuration.
  """
  def start_child(name, loader_module, source_config) do
    BuildLogger.debug(".", "RecordLoader.Supervisor: Starting child: #{name}, module: #{loader_module}")
    
    with {:ok, module} <- load_and_validate_module(loader_module),
         :ok <- validate_source_config(module, source_config) do
      
      # Prepare init argument for the loader
      init_arg = %{
        source: source_config, 
        module: module, 
        name: name
      }
      
      child_spec = {module, init_arg}
      BuildLogger.debug(".", "RecordLoader.Supervisor: Child spec: #{inspect(child_spec)}")

      case DynamicSupervisor.start_child(__MODULE__, child_spec) do
        {:ok, pid} ->
          BuildLogger.debug(".", "RecordLoader.Supervisor: Started #{name}, PID: #{inspect(pid)}")
          {:ok, pid}
        {:error, reason} ->
          BuildLogger.error(".", "RecordLoader.Supervisor: Failed to start child #{name}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stops a record loader agent for the given name.
  """
  def stop_child(name) do
    BuildLogger.debug(".", "RecordLoader.Supervisor: Stopping child: #{name}")
    
    case Registry.lookup(@registry_name, name) do
      [{pid, module}] ->
        # Check if process is still alive before trying to stop it
        if Process.alive?(pid) do
          # Call optional cleanup callback if available
          if function_exported?(module, :cleanup, 1) do
            try do
              apply(module, :cleanup, [pid])
            rescue
              error ->
                BuildLogger.warn(".", "RecordLoader.Supervisor: Cleanup failed for #{name}: #{inspect(error)}")
            end
          end
          
          # After cleanup, check if process is still alive before terminating
          if Process.alive?(pid) do
            case DynamicSupervisor.terminate_child(__MODULE__, pid) do
              :ok ->
                BuildLogger.debug(".", "RecordLoader.Supervisor: Stopped agent: #{name}")
                :ok
              {:error, :not_found} ->
                BuildLogger.debug(".", "RecordLoader.Supervisor: Agent #{name} was already stopped")
                :ok
              {:error, reason} ->
                BuildLogger.error(".", "RecordLoader.Supervisor: Failed to stop agent: #{name}, reason: #{inspect(reason)}")
                {:error, reason}
            end
          else
            BuildLogger.debug(".", "RecordLoader.Supervisor: Agent #{name} stopped during cleanup")
            :ok
          end
        else
          BuildLogger.debug(".", "RecordLoader.Supervisor: Agent #{name} already stopped")
          :ok
        end
      [] ->
        BuildLogger.debug(".", "RecordLoader.Supervisor: Agent #{name} not found in registry (already cleaned up)")
        :ok
    end
  end

  @doc """
  Gets a record loader agent by name.
  """
  def get_agent(name) do
    BuildLogger.debug(".", "RecordLoader.Supervisor: Getting agent: #{name}")
    
    case Registry.lookup(@registry_name, name) do
      [{pid, _module}] ->
        {:ok, pid}
      [] ->
        BuildLogger.warn(".", "RecordLoader.Supervisor: Agent not found: #{name}")
        {:error, :not_found}
    end
  end

  @doc """
  Returns the count of record loader agents managed by this supervisor.
  """
  def agent_count, do: DynamicSupervisor.which_children(__MODULE__) |> length

  @doc """
  Returns a list of active agent names.
  """
  def active_agent_names do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} ->
      case Registry.keys(@registry_name, pid) do
        [name] -> name
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Loads records from the specified agent with context.
  """
  def load_records(agent_name, context \\ %{}) do
    BuildLogger.debug(".", "RecordLoader.Supervisor: Loading records for agent: #{agent_name}")

    with {:ok, agent_pid} <- get_agent(agent_name),
         module <- get_agent_module(agent_name) do
      apply(module, :load_records, [agent_pid, context])
    else
      {:error, reason} ->
        BuildLogger.error(".", "RecordLoader.Supervisor: Failed to load records for #{agent_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Reads the next record from the specified agent.
  """
  def read_record(agent_name) do
    with {:ok, agent_pid} <- get_agent(agent_name),
         module <- get_agent_module(agent_name) do
      apply(module, :read_record, [agent_pid])
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Applies a filter to a record using the specified agent.
  """
  def apply_filter(agent_name, record, filter) do
    case get_agent_module(agent_name) do
      nil -> {:error, :agent_not_found}
      module -> apply(module, :apply_filter, [record, filter])
    end
  end

  @doc """
  Gets the count of records in the specified agent.
  """
  def get_agent_count(agent_name) do
    with {:ok, agent_pid} <- get_agent(agent_name),
         module <- get_agent_module(agent_name) do
      apply(module, :count, [agent_pid])
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all available record loaders that can be used.
  
  ## Returns
  
  List of available loaders with their information.
  """
  def list_available_loaders do
    LoaderRegistry.list_available_loaders()
  end

  @doc """
  Validates a loader configuration without actually starting the loader.
  
  ## Parameters
  
  * `loader_name` - Name of the loader module
  * `config` - Source configuration map to validate
  
  ## Returns
  
  * `:ok` if configuration is valid
  * `{:error, reason}` if invalid
  """
  def validate_loader_config(loader_name, config) do
    with {:ok, module} <- load_and_validate_module(loader_name) do
      validate_source_config(module, config)
    end
  end

  # Private functions

  defp load_and_validate_module(module_name) when is_binary(module_name) do
    BuildLogger.debug(".", "RecordLoader.Supervisor: Loading module: #{module_name}")
    
    # Try to convert string to existing atom first
    module = try do
      String.to_existing_atom("Elixir.#{module_name}")
    rescue
      ArgumentError ->
        # Module atom doesn't exist, create it
        String.to_atom("Elixir.#{module_name}")
    end
    
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        case LoaderRegistry.validate_implementation(module) do
          :ok -> 
            BuildLogger.debug(".", "RecordLoader.Supervisor: Module #{module} validated successfully")
            {:ok, module}
          {:error, reason} ->
            {:error, "Module #{module_name} validation failed: #{reason}"}
        end
      {:error, reason} ->
        {:error, "Failed to load module #{module_name}: #{reason}"}
    end
  end

  defp validate_source_config(module, config) do
    case apply(module, :validate_config, [config]) do
      :ok -> :ok
      {:error, reason} -> {:error, "Configuration validation failed: #{reason}"}
    end
  rescue
    error ->
      {:error, "Configuration validation error: #{Exception.message(error)}"}
  end

  defp get_agent_module(agent_name) do
    case Registry.lookup(@registry_name, agent_name) do
      [{_pid, module}] -> module
      [] ->
        BuildLogger.warn(".", "RecordLoader.Supervisor: No module found for agent: #{agent_name}")
        nil
    end
  end

  @impl true
  def init(_arg) do
    BuildLogger.info(".", "RecordLoader.Supervisor: Starting DynamicSupervisor")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end