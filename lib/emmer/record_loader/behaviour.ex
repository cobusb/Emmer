defmodule Emmer.RecordLoader.Behaviour do
  @moduledoc """
  Behaviour for record loader modules that load and process records from various sources.
  
  Record loaders are responsible for loading records (files, database entries, API responses, etc.)
  and providing them to processors in a consistent interface.
  
  ## Core Concepts
  
  * **Source** - Configuration defining where records come from (file path, database config, API endpoint)
  * **Record** - Individual unit of data to be processed (file content, database row, etc.)  
  * **Filter** - Rules for determining which records should be processed
  * **Context** - Additional information like build_id and root_folder_path for logging
  
  ## Example Implementation
  
      defmodule MyApp.RecordLoader.DatabaseLoader do
        @behaviour Emmer.RecordLoader.Behaviour
        
        def start_link(init_arg) do
          # Initialize loader (e.g., Agent, GenServer)
        end
        
        def child_spec(opts) do
          %{
            id: __MODULE__,
            start: {__MODULE__, :start_link, [opts]},
            type: :worker,
            restart: :temporary
          }
        end
        
        def load_records(loader_pid, context) do
          # Load records from source
          :ok
        end
        
        def read_record(loader_pid) do
          # Return next record or {:done}
          {:ok, %{"id" => 1, "data" => "..."}}
        end
        
        def apply_filter(record, filter) do
          # Check if record matches filter
          {:ok, true}
        end
        
        def count(loader_pid) do
          # Return total record count
          {:ok, 100}
        end
        
        def validate_config(config) do
          # Validate source configuration
          :ok
        end
        
        def supported_sources do
          # Return list of supported source types
          [:database, :api]
        end
      end
  """
  
  @type record :: map() | String.t() | any()
  @type filter :: map() | String.t() | any()
  @type source_config :: map()
  @type context :: map()
  @type init_arg :: map()
  
  @doc """
  Starts the record loader process.
  
  ## Parameters
  
  * `init_arg` - Map containing:
    * `:source` - Source configuration
    * `:module` - Module atom (for registry tracking)
    * `:name` - Unique name for the loader instance
    * Additional loader-specific options
  
  ## Returns
  
  * `{:ok, pid}` - Process ID of the started loader
  * `{:error, reason}` - Error if startup fails
  """
  @callback start_link(init_arg :: init_arg()) :: {:ok, pid()} | {:error, term()}
  
  @doc """
  Returns a child specification for supervisor usage.
  
  This allows the loader to be started under a DynamicSupervisor.
  
  ## Parameters
  
  * `opts` - Options passed to child_spec
  
  ## Returns
  
  Child specification map
  """
  @callback child_spec(opts :: term()) :: Supervisor.child_spec()
  
  @doc """
  Loads records from the configured source.
  
  This function should prepare records for reading but not necessarily load
  them all into memory at once (allows for streaming/pagination).
  
  ## Parameters
  
  * `loader_pid` - PID of the loader process
  * `context` - Map containing:
    * `:build_id` - Current build identifier
    * `:root_folder_path` - Root folder for logging
  
  ## Returns
  
  * `:ok` - Records loaded successfully
  * `{:error, reason}` - Error during loading
  """
  @callback load_records(loader_pid :: pid(), context :: context()) :: :ok | {:error, term()}
  
  @doc """
  Reads the next record from the loader.
  
  Records should be returned one at a time to support streaming large datasets.
  
  ## Parameters
  
  * `loader_pid` - PID of the loader process
  
  ## Returns
  
  * `{:ok, record}` - Next record
  * `{:done}` - No more records available
  * `{:error, reason}` - Error reading record
  """
  @callback read_record(loader_pid :: pid()) :: {:ok, record()} | {:done} | {:error, term()}
  
  @doc """
  Applies a filter to determine if a record should be processed.
  
  ## Parameters
  
  * `record` - Record to check
  * `filter` - Filter configuration (format depends on loader type)
  
  ## Returns
  
  * `{:ok, true}` - Record matches filter
  * `{:ok, false}` - Record doesn't match filter
  * `{:error, reason}` - Error applying filter
  """
  @callback apply_filter(record :: record(), filter :: filter()) :: {:ok, boolean()} | {:error, term()}
  
  @doc """
  Returns the total count of records available.
  
  ## Parameters
  
  * `loader_pid` - PID of the loader process
  
  ## Returns
  
  * `{:ok, count}` - Total number of records
  * `{:error, reason}` - Error getting count
  """
  @callback count(loader_pid :: pid()) :: {:ok, non_neg_integer()} | {:error, term()}
  
  @doc """
  Validates the source configuration before loading.
  
  ## Parameters
  
  * `config` - Source configuration map
  
  ## Returns
  
  * `:ok` - Configuration is valid
  * `{:error, reason}` - Configuration validation error
  """
  @callback validate_config(config :: source_config()) :: :ok | {:error, String.t()}
  
  @doc """
  Returns list of supported source types.
  
  This helps with loader discovery and validation.
  
  ## Returns
  
  List of atoms representing supported source types, e.g., [:file, :directory, :s3, :database]
  """
  @callback supported_sources() :: [atom()]
  
  @doc """
  Cleans up any resources used by the loader.
  
  This callback is optional. Called when the loader is being shut down.
  
  ## Parameters
  
  * `loader_pid` - PID of the loader process
  
  ## Returns
  
  Always returns `:ok`
  """
  @callback cleanup(loader_pid :: pid()) :: :ok
  
  @optional_callbacks [cleanup: 1]
end