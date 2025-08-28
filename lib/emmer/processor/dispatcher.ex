defmodule Emmer.Processor.Dispatcher do
  use GenServer
  require Logger

  alias Emmer.Builder.{Utilities, BuildLogger}

  @moduledoc """
  Dispatcher that coordinates between record loader agents and processor tasks.
  Reads records from agents, applies filters, and dispatches matching records to processors.
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Start task supervisor for processor tasks
    {:ok, supervisor} = Task.Supervisor.start_link(name: Emmer.ProcessorTaskSupervisor)

    {:ok, %{
      supervisor: supervisor
    }}
  end

  @doc """
  Starts processing records from a record loader agent through specified processors.
  """
  def start_processing(agent_name, processors, context, root_folder_path) do
    GenServer.call(__MODULE__, {:start_processing, agent_name, processors, context, root_folder_path})
  end

  @doc """
  Broadcasts a record processed progress update to the builder.
  """
  def record_processed(build_id, root_folder_path) do
    if build_id do
      Phoenix.PubSub.broadcast(Emmer.PubSub, "builder:#{root_folder_path}", {:build_progress, build_id, %{
        type: :record_processed,
        count: 1
      }})
    end
  end


  # GenServer callbacks
  def handle_call({:start_processing, agent_name, processors, context, root_folder_path}, _from, state) do
    # Check if agent exists before processing
    if not Emmer.RecordLoader.Supervisor.agent_exists?(agent_name) do
      {:reply, {:error, :agent_not_found}, state}
    else
      case load_records(agent_name, processors) do
        :ok ->
          BuildLogger.info(root_folder_path, "Started processing records from agent: #{agent_name}")
          # Process all records synchronously
          process_all_records(agent_name, processors, context, root_folder_path)
          
          # Clean up the agent since it's no longer needed
          Emmer.RecordLoader.Supervisor.stop_child(agent_name)
          
          # Return the processors list so post-processors can be run later
          {:reply, {:ok, processors}, state}

        :error ->
          {:reply, {:error, :error}, state}
      end
    end
  end


  # Handle task messages
  def handle_info({ref, {:ok, _pid}}, state) when is_reference(ref) do
    # Task started successfully, ignore
    {:noreply, state}
  end

  def handle_info({ref, :ok}, state) when is_reference(ref) do
    # Task completed successfully, ignore
    {:noreply, state}
  end

  def handle_info({ref, {:ok}}, state) when is_reference(ref) do
    # Task completed successfully with tuple format, ignore
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when is_reference(ref) do
    # Task completed, ignore
    BuildLogger.debug(".", "Task #{inspect(ref)} completed with reason: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info({ref, {:error, reason}}, state) when is_reference(ref) do
    # Task failed
    BuildLogger.error(".", "Task #{inspect(ref)} failed: #{inspect(reason)}")
    {:noreply, state}
  end


  # Private functions
  defp load_records(agent_name, processors) do
    case Emmer.RecordLoader.Supervisor.load_records(agent_name) do
      :ok ->
        :ok
      {:error, reason} ->
        BuildLogger.error(".", "Error loading records from agent #{agent_name}: #{reason}")
        :error
    end
  end


  defp process_all_records(agent_name, processors, context, root_folder_path) do
    process_record_loop(agent_name, processors, context, root_folder_path)
  end

  defp process_record_loop(agent_name, processors, context, root_folder_path) do
    case Emmer.RecordLoader.Supervisor.read_record(agent_name) do
      {:ok, record} ->
        # Separate per-file processors from post-processors
        {per_file_processors, post_processors} = separate_processors(processors)

        # Apply each per-file processor's filter to see if it should process this record
        BuildLogger.debug(root_folder_path, "Processing record: #{inspect(record)} with #{length(per_file_processors)} processors")
        Enum.each(per_file_processors, fn processor ->
          BuildLogger.debug(root_folder_path, "Checking processor '#{processor["name"] || "unknown"}' with filter: #{inspect(processor["filter"])}")
          case should_process_record(agent_name, record, processor) do
            {:ok, true} ->
              BuildLogger.info(root_folder_path, "✓ Processor '#{processor["name"]}' matches record: #{inspect(record)}")
              dispatch_processor_task(processor, record, context, root_folder_path)
            {:ok, false} ->
              BuildLogger.debug(root_folder_path, "✗ Processor '#{processor["name"]}' does not match record: #{inspect(record)}")
              :ok
            {:error, reason} ->
              BuildLogger.error(root_folder_path, "Filter error for processor #{processor["name"]}: #{reason}")
          end
        end)

        # Continue with next record
        process_record_loop(agent_name, processors, context, root_folder_path)

      {:done} ->
        BuildLogger.info(root_folder_path, "Finished processing all records from agent: #{agent_name}")
        
        # Return :ok to indicate processing completed successfully
        :ok

      {:error, reason} ->
        BuildLogger.error(root_folder_path, "Error reading record from agent #{agent_name}: #{reason}")
        :error
    end
  end

  defp should_process_record(agent_name, record, processor) do
    case processor["filter"] do
      nil ->
        # No filter means process all records
        {:ok, true}

      filter ->
        # Apply the filter using the agent's filter logic
        Emmer.RecordLoader.Supervisor.apply_filter(agent_name, record, filter)
    end
  end

  defp dispatch_processor_task(processor, record, context, root_folder_path) do
    # Validate processor configuration
    case validate_processor_config(processor) do
      {:error, reason} ->
        BuildLogger.error(root_folder_path, "Processor configuration error: #{reason}. Processor config: #{inspect(processor)}")
        record_processed(context[:build_id], root_folder_path)
        {:error, reason}

      :ok ->
        case Utilities.module_from_string(processor["module"]) do
          {:error, reason} ->
            BuildLogger.error(root_folder_path, "Processor module error: #{reason}. Processor config: #{inspect(processor)}")
            record_processed(context[:build_id], root_folder_path)
            {:error, reason}

          module ->
            node = processor["node"]
            build_id = context[:build_id]

            BuildLogger.debug(root_folder_path, "Dispatching record to processor: #{module}.build")

            # Verify the module has the required function before creating the task
            if function_exported?(module, :start_link, 3) do
              # Create the task
              task = Task.Supervisor.async_nolink(Emmer.ProcessorDispatcher, fn ->
                try do
                  result = if node do
                    # Remote processing
                    Node.spawn(node, module, :start_link, [record, processor, context])
                  else
                    # Local processing
                    apply(module, :start_link, [record, processor, context])
                  end

                  # Send progress update after processing
                  Emmer.Processor.Dispatcher.record_processed(build_id, root_folder_path)

                  result
                rescue
                  error ->
                    BuildLogger.error(root_folder_path, "Processor task failed: #{Exception.message(error)}")
                    Emmer.Processor.Dispatcher.record_processed(build_id, root_folder_path)
                    {:error, "Processor task failed: #{Exception.message(error)}"}
                end
              end)
            else
              BuildLogger.error(root_folder_path, "Processor module #{module} does not implement start_link/3 function")
              record_processed(context[:build_id], root_folder_path)
              {:error, "Module #{module} does not implement required start_link/3 function"}
            end
        end
    end
  end

  defp validate_processor_config(processor) when is_map(processor) do
    cond do
      not Map.has_key?(processor, "module") ->
        {:error, "Processor missing required 'module' field"}

      processor["module"] == nil ->
        {:error, "Processor 'module' field cannot be nil"}

      processor["module"] == "" ->
        {:error, "Processor 'module' field cannot be empty"}

      not is_binary(processor["module"]) ->
        {:error, "Processor 'module' field must be a string, got: #{inspect(processor["module"])}"}

      true ->
        :ok
    end
  end

  defp validate_processor_config(processor) do
    {:error, "Processor must be a map, got: #{inspect(processor)}"}
  end

  defp separate_processors(processors) do
    Enum.split_with(processors, fn processor ->
      # Post-processors are identified only by having "post_processor" flag set to true
      processor["post_processor"] != true
    end)
  end

  def run_post_processors(post_processors, context, root_folder_path) do
    BuildLogger.info(root_folder_path, "Running #{length(post_processors)} post-processors")

    Enum.each(post_processors, fn processor ->
      BuildLogger.info(root_folder_path, "Running post-processor: #{processor["name"]}")

      case validate_processor_config(processor) do
        {:error, reason} ->
          BuildLogger.error(root_folder_path, "Post-processor configuration error: #{reason}. Processor config: #{inspect(processor)}")

        :ok ->
          case Utilities.module_from_string(processor["module"]) do
            {:error, reason} ->
              BuildLogger.error(root_folder_path, "Post-processor module error: #{reason}. Processor config: #{inspect(processor)}")

            module ->
              dispatch_post_processor_task(module, processor, context, root_folder_path)
          end
      end
    end)
  end

  defp dispatch_post_processor_task(module, processor, context, root_folder_path) do
    BuildLogger.debug(root_folder_path, "Dispatching post-processor: #{module}")

    Task.Supervisor.async_nolink(Emmer.ProcessorDispatcher, fn ->
      # Post-processors get special treatment based on the module
      result = if module == Emmer.Processor.AssetBuilder do
        # Asset builders get the main source folder path from context
        # This is the root content folder, not the current processing folder
        main_source_folder_path = context[:main_source_folder_path] || context["main_source_folder_path"] ||
                                  context[:source_folder_path] || context["source_folder_path"] || root_folder_path

        # Call the AssetBuilder wrapper with the standard 3-parameter format
        apply(module, :build, [%{"path" => main_source_folder_path}, processor, context])
      else
        # Regular post-processors get the full context
        apply(module, :build, [context, processor, context])
      end

      # Send progress update after processing
      Emmer.Processor.Dispatcher.record_processed(context[:build_id], root_folder_path)

      # Normalize return value for task supervisor
      case result do
        {:ok, _files} -> :ok
        {:error, reason} -> {:error, reason}
        other -> other
      end
    end)
  end
end
