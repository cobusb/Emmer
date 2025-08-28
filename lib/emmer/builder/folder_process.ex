defmodule Emmer.Builder.FolderProcess do
  use Task

  alias Emmer.Builder.{Utilities, BuildLogger}

  def start_link(source_path, build_id, context, folder_config, root_folder_path) do
    # Use the supervised task supervisor for the initial folder process too
    Task.Supervisor.start_child(Emmer.FolderProcessSupervisor, fn ->
      process_folder(source_path, build_id, context, folder_config, root_folder_path)
    end)
  end

  def process_folder(source_path, build_id, context, folder_config, root_folder_path) do

    with {:ok, folder_config} <- load_or_inherit_folder_config(source_path, build_id, folder_config) do

      # Broadcast folder started progress update
      BuildLogger.debug(root_folder_path, "#{build_id} Broadcasting folder started for root_folder_path: #{root_folder_path}")
      Phoenix.PubSub.broadcast(Emmer.PubSub, "builder:#{root_folder_path}", {:build_progress, build_id, %{
        type: :folder_started,
        folder: source_path
      }})

        # Create a unique agent name for this folder that includes the build_id
        agent_name = "folder_#{build_id}_#{String.replace(source_path, "/", "_")}"

        processors = folder_config["config"]["processors"] || []
        record_loader_module = folder_config["record_loader"] || "Emmer.RecordLoader.FileLoader"
        record_loader_config = folder_config["record_loader_config"] || %{"path" => source_path}

        BuildLogger.debug(root_folder_path, "#{build_id} Record Loader module for agent #{agent_name}: #{record_loader_module}")

        if length(processors) > 0 do
          BuildLogger.debug(root_folder_path, "#{build_id} Found #{length(processors)} processors.")

          # Module loaded successfully, proceed
        case Emmer.RecordLoader.Supervisor.find_or_create(
          agent_name,
          record_loader_module,
          record_loader_config
        ) do
            {:ok, _agent_pid} ->
              BuildLogger.debug(root_folder_path, "#{build_id} Created record loader agent for #{agent_name}")

              # Broadcast agent created progress update
              Phoenix.PubSub.broadcast(Emmer.PubSub, "builder:#{root_folder_path}", {:build_progress, build_id, %{
                type: :agent_created,
                agent: agent_name
              }})

              context = Utilities.deep_merge(context, folder_config["data"] || %{})
              # Add build_id and source folder paths to context for processors
              context = context
                |> Map.put(:build_id, build_id)
                |> Map.put(:project_root, root_folder_path)  # Add project root for processors
                |> then(fn ctx ->
                  # If this is the first folder being processed, set the main source folder path
                  # Otherwise preserve the existing main source folder path
                  if Map.has_key?(ctx, :main_source_folder_path) do
                    Map.put(ctx, :source_folder_path, source_path)
                  else
                    ctx
                    |> Map.put(:main_source_folder_path, source_path)
                    |> Map.put(:source_folder_path, source_path)
                  end
                end)
              BuildLogger.debug(root_folder_path, "#{build_id} Deep merge completed: #{agent_name}")
              BuildLogger.debug(root_folder_path, "#{build_id} #{agent_name} context: #{inspect(context)}")

              # Use the new processor dispatcher
              # The dispatcher will return the processors list after processing all records
              dispatcher_result = Emmer.Processor.Dispatcher.start_processing(agent_name, processors, context, root_folder_path)

              # Get all folders in the directory (non-recursive), excluding configured directories
              ignore_folders = folder_config["ignore_folders"] || ["node_modules", ".git", ".DS_Store", "dist", "build", "_site", ".next", ".nuxt", "coverage", "tmp"]

              folders =
                source_path
                |> File.ls!()
                |> Enum.map(&Path.join(source_path, &1))
                |> Enum.filter(&File.dir?/1)
                |> Enum.reject(fn folder ->
                  folder_name = Path.basename(folder)
                  # Exclude directories from the ignore list
                  folder_name in ignore_folders
                end)

              BuildLogger.debug(root_folder_path, "#{build_id} Subfolders in #{source_path}: #{inspect(folders)}")

              # Create a new folder process for each subfolder using the dedicated folder process supervisor
              subfolder_tasks = Enum.map(folders, fn folder ->
                BuildLogger.debug(root_folder_path, "#{build_id} Starting folder process for #{folder}")
                Task.Supervisor.async_nolink(Emmer.FolderProcessSupervisor, fn ->
                  Emmer.Builder.FolderProcess.process_folder(folder, build_id, context, folder_config, root_folder_path)
                end)
              end)

              # Wait for all subfolders to complete before marking this folder as complete
              Enum.each(subfolder_tasks, fn task ->
                Task.await(task, :infinity)
              end)

              # Now run post-processors after all subfolders are complete
              BuildLogger.debug(root_folder_path, "#{build_id} Dispatcher result: #{inspect(dispatcher_result)}")
              case dispatcher_result do
                {:ok, all_processors} ->
                  # Separate regular processors from post-processors
                  post_processors = Enum.filter(all_processors, fn processor ->
                    processor["post_processor"] == true
                  end)
                  
                  BuildLogger.debug(root_folder_path, "#{build_id} Found #{length(post_processors)} post-processors out of #{length(all_processors)} total processors")
                  
                  if length(post_processors) > 0 do
                    BuildLogger.info(root_folder_path, "#{build_id} Running #{length(post_processors)} post-processors for #{source_path}")
                    Emmer.Processor.Dispatcher.run_post_processors(post_processors, context, root_folder_path)
                  end
                other ->
                  # No processors returned or error, skip post-processors
                  BuildLogger.debug(root_folder_path, "#{build_id} No processors returned from dispatcher or error: #{inspect(other)}")
                  :ok
              end

              # Now broadcast folder completion after all subfolders are done AND post-processors have run
              Phoenix.PubSub.broadcast(Emmer.PubSub, "builder:#{root_folder_path}", {:build_progress, build_id, %{
                type: :folder_completed,
                folder: source_path
              }})

              {:ok, agent_name}

            {:error, reason} ->
              # Module couldn't be loaded
              BuildLogger.error(root_folder_path, "#{build_id} Failed to load module #{record_loader_module}: #{inspect(reason)}")
              # Broadcast error to builder
              Phoenix.PubSub.broadcast(Emmer.PubSub, "builder:#{root_folder_path}", {:build_error, build_id, "Failed to load module #{record_loader_module}: #{inspect(reason)}"})
              {:error, "Failed to load module #{record_loader_module}: #{inspect(reason)}"}
            end
          else
            BuildLogger.warn(root_folder_path, "#{build_id} No processors found for #{agent_name} - skipping folder.")
            # Clean up any existing agent for this folder
            Emmer.RecordLoader.Supervisor.stop_child(agent_name)

            # Still need to process subfolders and broadcast completion
            ignore_folders = folder_config["ignore_folders"] || ["node_modules", ".git", ".DS_Store", "dist", "build", "_site", ".next", ".nuxt", "coverage", "tmp"]

            folders =
              source_path
              |> File.ls!()
              |> Enum.map(&Path.join(source_path, &1))
              |> Enum.filter(&File.dir?/1)
              |> Enum.reject(fn folder ->
                folder_name = Path.basename(folder)
                folder_name in ignore_folders
              end)

            BuildLogger.debug(root_folder_path, "#{build_id} Subfolders in #{source_path}: #{inspect(folders)}")

            # Create subfolder processes even if this folder has no processors
            subfolder_tasks = Enum.map(folders, fn folder ->
              BuildLogger.debug(root_folder_path, "#{build_id} Starting folder process for #{folder}")
              Task.Supervisor.async_nolink(Emmer.FolderProcessSupervisor, fn ->
                Emmer.Builder.FolderProcess.process_folder(folder, build_id, context, folder_config, root_folder_path)
              end)
            end)

            # Wait for all subfolders to complete
            Enum.each(subfolder_tasks, fn task ->
              Task.await(task, :infinity)
            end)

            # Broadcast completion after subfolders are done
            Phoenix.PubSub.broadcast(Emmer.PubSub, "builder:#{root_folder_path}", {:build_progress, build_id, %{
              type: :folder_completed,
              folder: source_path
            }})

            {:ok, agent_name}
        end

    else
      {:error, error_msg} ->
        BuildLogger.error(root_folder_path, "#{build_id} #{source_path} - #{error_msg}")
        if build_id do
          Phoenix.PubSub.broadcast(Emmer.PubSub, "builder:#{root_folder_path}", {:build_error, build_id, "Folder processing failed: #{error_msg}"})
        end
        {:error, error_msg}
    end
  end

  defp load_or_inherit_folder_config(source_path, build_id, folder_config) when map_size(folder_config) > 0 do
    case Utilities.load_yaml(source_path, "folder", build_id) do
      {:ok, new_folder_config} ->
        BuildLogger.debug(source_path, "#{build_id} #{source_path} - new folder config loaded.")
        {:ok, new_folder_config}
      {:error, error_msg} ->
        BuildLogger.debug(source_path, "#{build_id} #{source_path} - inheriting parent folder config (excluding post-processors).")
        # Remove post-processors from inherited config - they should only run where explicitly configured
        inherited_config = remove_post_processors_from_config(folder_config)
        {:ok, inherited_config}
    end
  end

  defp load_or_inherit_folder_config(source_path, build_id, folder_config) when map_size(folder_config) == 0 do
    case Utilities.load_yaml(source_path, "folder", build_id) do
      {:ok, new_folder_config} ->
        BuildLogger.debug(source_path, "#{build_id} #{source_path} - new folder config loaded.")
        {:ok, new_folder_config}
      {:error, error_msg} ->
        BuildLogger.error(source_path, "#{build_id} #{source_path} - #{error_msg}")
        {:error, error_msg}
    end
  end

  defp remove_post_processors_from_config(folder_config) do
    case folder_config do
      %{"config" => %{"processors" => processors} = config} = folder_config ->
        # Filter out post-processors (identified by post_processor: true flag)
        regular_processors = Enum.reject(processors, fn processor ->
          processor["post_processor"] == true
        end)

        updated_config = Map.put(config, "processors", regular_processors)
        Map.put(folder_config, "config", updated_config)

      _ ->
        # No processors config found, return as-is
        folder_config
    end
  end
end
