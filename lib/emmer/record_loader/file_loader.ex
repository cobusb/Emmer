defmodule Emmer.RecordLoader.FileLoader do
  use Agent
  @behaviour Emmer.RecordLoader.Behaviour

  @moduledoc """
  Record loader agent for loading files from a directory.
  Uses regex patterns for filtering.
  """
  
  alias Emmer.Builder.BuildLogger

  @registry_name Emmer.RecordLoader.Registry

  @impl true
  def start_link(%{source: source, module: module, name: name}) do
    BuildLogger.debug(".", "FileLoader: Starting with source: #{inspect(source)}, name: #{name}")
    Agent.start_link(fn ->
      # Register this agent in the Registry with module as metadata
      Registry.register(@registry_name, name, module)
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
    BuildLogger.debug(context[:root_folder_path] || ".", "FileLoader: Starting load_records for agent PID: #{inspect(agent_pid)}")

    try do
      Agent.update(agent_pid, fn state ->
        BuildLogger.debug(context[:root_folder_path] || ".", "FileLoader: Source path: #{inspect(state.source["path"])}")

        source_path = state.source["path"]
        BuildLogger.info(context[:root_folder_path] || ".", "FileLoader: Loading files from directory: #{source_path}")

        # Load all files from the directory
        files =
          source_path
          |> File.ls!()
          |> Enum.filter(fn entry ->
            full_path = Path.join(source_path, entry)
            File.regular?(full_path)
          end)
          |> Enum.map(fn file -> Path.join(source_path, file) end)

        BuildLogger.info(context[:root_folder_path] || ".", "FileLoader: Found #{length(files)} files in directory")

        %{state | files: files, total_count: length(files)}
      end)

      BuildLogger.debug(context[:root_folder_path] || ".", "FileLoader: load_records completed successfully")
      :ok
    rescue
      error ->
        BuildLogger.error(context[:root_folder_path] || ".", "FileLoader: Error in load_records: #{inspect(error)}")
        {:error, Exception.message(error)}
    end
  end

  @impl true
  def read_record(agent_pid) do
    Agent.get_and_update(agent_pid, fn state ->
      case Enum.at(state.files, state.current_index) do
        nil ->
          # No more files, return done and keep state unchanged
          {{:done}, state}
        file ->
          # Return the file and update the state atomically
          updated_state = %{state | current_index: state.current_index + 1}
          {{:ok, file}, updated_state}
      end
    end)
  end

  @impl true
  def apply_filter(record, filter) do
    case filter do
      %{"regex" => regex_pattern} ->
        case Regex.compile(regex_pattern) do
          {:ok, regex} -> {:ok, Regex.match?(regex, record)}
          {:error, error} -> {:error, "Invalid regex pattern: #{error}"}
        end

      %{"extension" => extension} ->
        file_extension = Path.extname(record)
        {:ok, file_extension == extension or file_extension == ".#{extension}"}

      %{"pattern" => pattern} ->
        {:ok, String.contains?(record, pattern)}

      _ ->
        {:error, "Unknown filter type for file loader"}
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
        {:error, "FileLoader requires a 'path' field with a valid directory path"}
    end
  end

  @impl true
  def supported_sources do
    [:file, :directory]
  end

  @impl true
  def cleanup(agent_pid) do
    # Optional cleanup - just stop the agent gracefully
    Agent.stop(agent_pid, :normal)
    :ok
  end

  def terminate(_reason, _state) do
    # Agent will be stopped by the Registry when remove_agent is called
    :ok
  end

  @doc """
  Stops the agent process.
  """
  def stop(agent_pid) do
    Agent.stop(agent_pid)
  end
end
