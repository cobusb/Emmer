defmodule Emmer.RecordLoader.JsonLoader do
  use Agent
  @behaviour Emmer.RecordLoader.Behaviour

  @moduledoc """
  Record loader agent for loading JSON files.
  Example of how other RecordLoader modules would implement the same pattern.
  """
  
  alias Emmer.Builder.BuildLogger

  @impl true
  def start_link(%{source: source, module: module, name: name}) do
    BuildLogger.debug(".", "JsonLoader: Starting with source: #{inspect(source)}, name: #{name}")
    Agent.start_link(fn ->
      # Register this agent in the Registry with module as metadata
      Registry.register(Emmer.RecordLoader.Registry, name, module)
      %{
        source: source,
        files: [],
        current_index: 0,
        total_count: 0,
        module: module
      }
    end)
  end

  @impl true
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary
    }
  end

  @impl true
  def load_records(agent_pid, context \\ %{}) do
    BuildLogger.debug(context[:root_folder_path] || ".", "JsonLoader: Starting load_records")
    
    try do
      Agent.update(agent_pid, fn state ->
        BuildLogger.debug(context[:root_folder_path] || ".", "JsonLoader: Loading JSON records from #{state.source["path"]}")
        source_path = state.source["path"]
        # Load all JSON files from the directory
        files =
          source_path
          |> File.ls!()
          |> Enum.filter(fn entry ->
            full_path = Path.join(source_path, entry)
            File.regular?(full_path) and Path.extname(entry) == ".json"
          end)
          |> Enum.map(fn file -> Path.join(source_path, file) end)

        BuildLogger.info(context[:root_folder_path] || ".", "JsonLoader: Found #{length(files)} JSON files")
        %{state | files: files, total_count: length(files)}
      end)
      
      :ok
    rescue
      error ->
        BuildLogger.error(context[:root_folder_path] || ".", "JsonLoader: Error in load_records: #{inspect(error)}")
        {:error, Exception.message(error)}
    end
  end

  @impl true
  def read_record(agent_pid) do
    Agent.get_and_update(agent_pid, fn state ->
      case Enum.at(state.files, state.current_index) do
        nil ->
          # No more JSON files, returning done
          {{:done}, state}
        file ->
          # Read and parse JSON file
          case File.read(file) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, json_data} ->
                  updated_state = %{state | current_index: state.current_index + 1}
                  {{:ok, json_data}, updated_state}
                {:error, reason} ->
                  {{:error, "JSON parse error: #{inspect(reason)}"}, state}
              end
            {:error, reason} ->
              {{:error, "File read error: #{inspect(reason)}"}, state}
          end
      end
    end)
  end

  @impl true
  def apply_filter(record, filter) do
    case filter do
      %{"field" => field_name, "value" => expected_value} ->
        # Filter by JSON field value
        case Map.get(record, field_name) do
          ^expected_value -> {:ok, true}
          _ -> {:ok, false}
        end

      %{"field_exists" => field_name} ->
        # Filter by field existence
        {:ok, Map.has_key?(record, field_name)}

      _ ->
        {:error, "Unknown filter type for JSON loader"}
    end
  end

  @impl true
  def count(agent_pid) do
    Agent.get(agent_pid, fn state -> {:ok, state.total_count} end)
  end

  @impl true
  def validate_config(config) do
    case config do
      %{"path" => path} when is_binary(path) ->
        if File.exists?(path) and File.dir?(path) do
          :ok
        else
          {:error, "Path does not exist or is not a directory: #{path}"}
        end
      _ ->
        {:error, "JsonLoader requires a 'path' field with a valid directory path"}
    end
  end

  @impl true
  def supported_sources do
    [:file, :directory, :json]
  end

  @impl true
  def cleanup(agent_pid) do
    # Optional cleanup - just stop the agent gracefully
    Agent.stop(agent_pid, :normal)
    :ok
  end

  def terminate(_reason, _state) do
    :ok
  end

  @doc """
  Stops the agent process.
  """
  def stop(agent_pid) do
    Agent.stop(agent_pid)
  end
end
