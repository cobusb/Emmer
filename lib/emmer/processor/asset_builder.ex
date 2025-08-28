defmodule Emmer.Processor.AssetBuilder do
  @moduledoc """
  Configurable asset builder processor that dynamically loads framework-specific builders.
  
  This processor acts as a bridge between Emmer's processing system and various
  asset building tools (Tailwind, esbuild, Vite, etc.). It dynamically loads
  the appropriate builder module based on configuration.
  
  ## Configuration
  
  The processor expects the following configuration in folder.yaml:
  
      processors:
        - name: "assets"
          module: "Emmer.Processor.AssetBuilder"
          builder: "Emmer.AssetBuilder.TailwindEsbuild"  # Module name
          builder_config:
            css_entry: "styles/main.css"
            js_entry: "js/main.js"
            plugins: ["daisyui"]
          output_dir: "dist/assets"  # Optional, relative to project root
          output_subdir: "assets"    # Deprecated, use output_dir instead
          filter:
            regex: "\\.(css|js|ts)$"
  
  ## Supported Builders
  
  Any module that implements `Emmer.AssetBuilder.Behaviour` can be used.
  Built-in builders include:
  
  * `Emmer.AssetBuilder.TailwindEsbuild` - Tailwind CSS + esbuild
  
  Users can create their own builders by implementing the behaviour.
  """
  
  use Task
  alias Emmer.Builder.BuildLogger
  
  def start_link(record, processor, context) do
    Task.start_link(__MODULE__, :build, [record, processor, context])
  end
  
  def build(record, processor, context) do
    source_path = record["path"]
    build_id = context[:build_id] || "unknown"
    root_folder_path = context["root_folder_path"] || context[:root_folder_path] || source_path
    
    # Determine output path
    # Get the actual project root (where emmer.config.yaml is) from context
    project_root = context[:project_root] || context["project_root"] || 
                   context[:root_folder_path] || context["root_folder_path"] ||
                   root_folder_path
    
    # Use output_dir from processor config if specified, otherwise fall back to default behavior
    output_path = case processor["output_dir"] do
      nil -> 
        # No output_dir specified, use old behavior for backward compatibility
        output_subdir = processor["output_subdir"] || "assets"
        case context["output_dir"] do
          nil -> Path.join(source_path, output_subdir)
          output_dir -> Path.join(output_dir, output_subdir)
        end
      output_dir ->
        # output_dir specified, resolve it relative to project root (like FileCopy)
        if Path.absname(output_dir) == output_dir do
          # Already absolute path, use as-is
          output_dir
        else
          # Relative path, make it relative to the project root
          Path.join(project_root, output_dir)
        end
    end
    
    builder_config = processor["builder_config"] || %{}
    builder_module_name = processor["builder"]
    
    BuildLogger.info(root_folder_path, "#{build_id} Starting asset build for #{source_path}")
    BuildLogger.debug(root_folder_path, "#{build_id} Builder: #{builder_module_name}")
    BuildLogger.debug(root_folder_path, "#{build_id} Output path: #{output_path}")
    
    case load_builder_module(builder_module_name, root_folder_path, build_id) do
      {:ok, builder_module} ->
        build_with_module(builder_module, source_path, output_path, builder_config, build_id, root_folder_path, context)
      {:error, reason} ->
        BuildLogger.error(root_folder_path, "#{build_id} Failed to load asset builder '#{builder_module_name}': #{reason}")
        {:error, reason}
    end
  end
  
  defp load_builder_module(module_name, root_folder_path, build_id) when is_binary(module_name) do
    BuildLogger.debug(root_folder_path, "#{build_id} Loading asset builder module: #{module_name}")
    
    # Try to convert string to existing atom first
    try do
      module_atom = String.to_existing_atom("Elixir.#{module_name}")
      case Code.ensure_loaded(module_atom) do
        {:module, ^module_atom} ->
          validate_behaviour(module_atom, root_folder_path, build_id)
        {:error, reason} ->
          {:error, "Module #{module_name} could not be loaded: #{reason}"}
      end
    rescue
      ArgumentError ->
        # Module atom doesn't exist, try to load it dynamically
        load_module_dynamically(module_name, root_folder_path, build_id)
    end
  end
  
  defp load_module_dynamically(module_name, root_folder_path, build_id) do
    BuildLogger.debug(root_folder_path, "#{build_id} Attempting dynamic load of module: #{module_name}")
    
    # Convert string to atom (creates new atom if needed)
    module_atom = String.to_atom("Elixir.#{module_name}")
    
    case Code.ensure_loaded(module_atom) do
      {:module, ^module_atom} ->
        validate_behaviour(module_atom, root_folder_path, build_id)
      {:error, :nofile} ->
        {:error, "Asset builder module '#{module_name}' not found. Make sure it's available in the code path."}
      {:error, reason} ->
        {:error, "Failed to load module '#{module_name}': #{reason}"}
    end
  end
  
  defp validate_behaviour(module, root_folder_path, build_id) do
    required_functions = [
      {:build, 4},
      {:supported_extensions, 0},
      {:validate_config, 1}
    ]
    
    missing_functions = Enum.reject(required_functions, fn {func, arity} ->
      function_exported?(module, func, arity)
    end)
    
    case missing_functions do
      [] -> 
        BuildLogger.debug(root_folder_path, "#{build_id} Module #{module} successfully validated")
        {:ok, module}
      functions -> 
        missing_list = Enum.map(functions, fn {func, arity} -> "#{func}/#{arity}" end)
        {:error, "Module #{module} does not implement required functions: #{Enum.join(missing_list, ", ")}"}
    end
  end
  
  defp build_with_module(builder_module, source_path, output_path, builder_config, build_id, root_folder_path, context) do
    BuildLogger.debug(root_folder_path, "#{build_id} Validating builder config")
    
    case apply(builder_module, :validate_config, [builder_config]) do
      :ok ->
        BuildLogger.info(root_folder_path, "#{build_id} Building assets with #{builder_module}")
        
        # Pass full context to builders - they might need other info
        case apply(builder_module, :build, [source_path, output_path, builder_config, context]) do
          {:ok, built_files} ->
            BuildLogger.info(root_folder_path, "#{build_id} Successfully built #{length(built_files)} asset files")
            Enum.each(built_files, fn file ->
              BuildLogger.debug(root_folder_path, "#{build_id} Built: #{file}")
            end)
            
            # Broadcast progress update
            broadcast_asset_completion(build_id, length(built_files), root_folder_path)
            
            {:ok}
          {:error, reason} ->
            BuildLogger.error(root_folder_path, "#{build_id} Asset build failed: #{reason}")
            {:error, reason}
        end
      {:error, reason} ->
        BuildLogger.error(root_folder_path, "#{build_id} Invalid builder config: #{reason}")
        {:error, "Configuration validation failed: #{reason}"}
    end
  end
  
  defp broadcast_asset_completion(build_id, file_count, root_folder_path) do
    if root_folder_path do
      Phoenix.PubSub.broadcast(Emmer.PubSub, "builder:#{root_folder_path}", {
        :build_progress, 
        build_id, 
        %{
          type: :assets_built,
          count: file_count
        }
      })
    end
  end
  
  @doc """
  Lists all available asset builders that can be used with this processor.
  
  ## Returns
  
  List of available builders with their information.
  """
  def list_available_builders do
    Emmer.AssetBuilder.Registry.list_available_builders()
  end
  
  @doc """
  Validates a builder configuration without actually running the build.
  
  ## Parameters
  
  * `builder_name` - Name of the builder module
  * `config` - Configuration map to validate
  
  ## Returns
  
  * `:ok` if configuration is valid
  * `{:error, reason}` if invalid
  """
  def validate_builder_config(builder_name, config) do
    # For validation, we don't need root_folder_path or build_id
    case load_builder_module(builder_name, ".", "validation") do
      {:ok, builder_module} ->
        apply(builder_module, :validate_config, [config])
      {:error, reason} ->
        {:error, "Failed to load builder: #{reason}"}
    end
  end
end