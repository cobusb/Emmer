defmodule Emmer.Processor.Image do
  @moduledoc """
  A flexible image processing processor that uses the Image library (image hex package).
  
  This processor allows dynamic execution of Image module functions through YAML configuration,
  supporting the library's pipeline approach for chaining operations.
  
  ## Configuration
  
  * `output_dir` - Directory to save processed images (required)
  * `preserve_structure` - Maintain original directory structure (optional, default: false)
  * `operations` - List of operations to perform on each image (required)
  * `filter` - Standard Emmer filter to select files
  
  ## Operations Configuration
  
  Each operation in the `operations` list should have:
  * `module` - The Image module to use (e.g., "Image")
  * `function` - The function to call (e.g., "resize", "thumbnail")
  * `args` - Array of arguments (optional after the image argument)
  
  Arguments can be:
  * Simple values: strings, numbers, booleans
  * Atoms: strings starting with ":" (e.g., ":jpeg")
  * Keyword lists: objects with "opts" key containing key-value pairs
  * Data placeholders: strings starting with "__DATA." (e.g., "__DATA.site_name__")
  
  ## Examples
  
  ### Simple resize and save operation
  ```yaml
  processors:
    - name: "resize_images"
      module: "Emmer.Processor.Image"
      filter:
        regex: "\\.(jpg|png|gif)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        - module: "Image"
          function: "resize"
          args: [200, 150]
        - module: "Image"
          function: "write!"
          args: ["__OUTPUT_PATH__"]
  ```
  
  ### Complex pipeline with multiple operations
  ```yaml
  processors:
    - name: "process_photos"
      module: "Emmer.Processor.Image"
      filter:
        regex: "\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        - module: "Image"
          function: "thumbnail"
          args: [300, [
            opts: {
              crop: ":center",
              quality: 85
            }
          ]]
        - module: "Image"
          function: "write!"
          args: ["__OUTPUT_PATH__"]
  ```
  
  ### Text overlay with data
  ```yaml
  processors:
    - name: "add_site_branding"
      module: "Emmer.Processor.Image"
      output_dir: "dist/images/branded"
      filter:
        regex: "\\\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        - module: "Image"  
          function: "text!"
          args: ["__DATA.site_name__", [
            opts: {
              x: 50,
              y: 50,
              font_size: 24,
              color: "white"
            }
          ]]
        - module: "Image"
          function: "write!"
          args: ["__OUTPUT_PATH__"]
  ```
  """
  
  use Task
  alias Emmer.Builder.BuildLogger
  
  def start_link(record, processor, context) do
    Task.start_link(__MODULE__, :build, [record, processor, context])
  end
  
  def build(record, processor, context) do
    build_id = context[:build_id] || "unknown"
    root_folder_path = context[:root_folder_path] || context["root_folder_path"] || "."
    
    # Extract source path from record
    source_path = case record do
      %{"path" => path} -> path
      path when is_binary(path) -> path
      _ ->
        BuildLogger.error(root_folder_path, "#{build_id} Image: Invalid record format")
        {:error, "Invalid record format"}
    end
    
    # Validate processor configuration
    case validate_config(processor) do
      {:error, reason} ->
        BuildLogger.error(root_folder_path, "#{build_id} Image configuration error: #{reason}")
        {:error, reason}
      
      :ok ->
        process_image(source_path, processor, context, build_id, root_folder_path)
    end
  end
  
  defp validate_config(processor) do
    cond do
      !Map.has_key?(processor, "output_dir") ->
        {:error, "Missing required 'output_dir' configuration"}
      
      !Map.has_key?(processor, "operations") ->
        {:error, "Missing required 'operations' configuration"}
      
      !is_list(processor["operations"]) ->
        {:error, "'operations' must be a list"}
      
      Enum.empty?(processor["operations"]) ->
        {:error, "'operations' list cannot be empty"}
      
      true ->
        validate_operations(processor["operations"])
    end
  end
  
  defp validate_operations(operations) do
    Enum.reduce_while(operations, :ok, fn operation, _acc ->
      case validate_operation(operation) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
  
  defp validate_operation(operation) do
    cond do
      !is_map(operation) ->
        {:error, "Each operation must be a map"}
      
      !Map.has_key?(operation, "module") ->
        {:error, "Operation missing 'module' field"}
      
      !Map.has_key?(operation, "function") ->
        {:error, "Operation missing 'function' field"}
      
      true ->
        :ok
    end
  end
  
  defp process_image(source_path, processor, context, build_id, root_folder_path) do
    BuildLogger.debug(root_folder_path, "#{build_id} Image: Processing #{source_path}")
    
    # Get output directory configuration
    output_dir = processor["output_dir"]
    preserve_structure = processor["preserve_structure"] || false
    
    # Resolve output directory relative to project root
    project_root = context[:project_root] || context["project_root"] || 
                   context[:root_folder_path] || context["root_folder_path"] ||
                   root_folder_path
    
    absolute_output_dir = if Path.absname(output_dir) == output_dir do
      output_dir
    else
      Path.join(project_root, output_dir)
    end
    
    # Determine output path
    filename = Path.basename(source_path)
    output_path = if preserve_structure do
      relative_path = Path.relative_to(source_path, project_root)
      Path.join(absolute_output_dir, relative_path)
    else
      Path.join(absolute_output_dir, filename)
    end
    
    # Create output directory
    output_dir_path = Path.dirname(output_path)
    File.mkdir_p!(output_dir_path)
    
    # Execute the operations pipeline
    case execute_operations(source_path, output_path, processor["operations"], context, build_id, root_folder_path) do
      {:ok, result_path} ->
        BuildLogger.info(root_folder_path, "#{build_id} Image: Processed #{filename} to #{result_path}")
        {:ok}
      
      {:error, reason} ->
        BuildLogger.error(root_folder_path, "#{build_id} Image: Failed to process #{filename}: #{reason}")
        {:error, reason}
    end
  end
  
  defp execute_operations(source_path, output_path, operations, context, build_id, root_folder_path) do
    # Start with the source path as the initial value
    initial_value = source_path
    
    # Execute operations in sequence, piping results
    result = Enum.reduce_while(operations, {:ok, initial_value}, fn operation, {:ok, current_value} ->
      # Don't proceed if current_value is an error tuple
      case current_value do
        {:error, _reason} = error ->
          {:halt, error}
        _ ->
          case execute_operation(operation, current_value, output_path, context, build_id, root_folder_path) do
            {:ok, new_value} -> 
              # Unwrap nested {:ok, value} tuples that some Image functions return
              unwrapped_value = case new_value do
                {:ok, actual_value} -> actual_value
                value -> value
              end
              {:cont, {:ok, unwrapped_value}}
            error -> {:halt, error}
          end
      end
    end)
    
    case result do
      {:ok, _final_value} -> {:ok, output_path}
      error -> error
    end
  end
  
  defp execute_operation(operation, current_value, output_path, context, build_id, root_folder_path) do
    module_name = operation["module"]
    function_name = operation["function"]
    args = operation["args"] || []
    
    BuildLogger.debug(root_folder_path, "#{build_id} Image: Executing #{module_name}.#{function_name}")
    
    # Load the module
    case load_module(module_name) do
      {:ok, module} ->
        # Special handling for different function types
        function_atom = String.to_atom(function_name)
        
        # Ensure args is a list
        args_list = case args do
          list when is_list(list) -> list
          single_value -> [single_value]
        end
        
        # Prepare arguments based on function type
        {prepared_args, check_arity} = case function_name do
          "open!" ->
            # open! takes the path as first argument
            prepared = prepare_argument_list(args_list, output_path, context)
            {[current_value | prepared], length(prepared) + 1}
          
          _ ->
            # Most Image functions take the image as first argument
            # Prepend the current image value to the arguments
            prepared = prepare_argument_list(args_list, output_path, context)
            all_args = [current_value | prepared]
            {all_args, length(all_args)}
        end
        
        # Try to find the correct arity for the function
        case find_function_arity(module, function_atom, prepared_args) do
          {:ok, arity, final_args} ->
            BuildLogger.debug(root_folder_path, "#{build_id} Image: Calling #{module_name}.#{function_name}/#{arity} with args: #{inspect(final_args)}")
            # Execute the function
            try do
              result = apply(module, function_atom, final_args)
              BuildLogger.debug(root_folder_path, "#{build_id} Image: #{module_name}.#{function_name}/#{arity} completed successfully")
              {:ok, result}
            rescue
              error ->
                {:error, "Error executing #{module_name}.#{function_name}: #{Exception.message(error)}"}
            catch
              :exit, reason ->
                {:error, "Function #{module_name}.#{function_name} exited: #{inspect(reason)}"}
            end
          
          {:error, reason} ->
            {:error, reason}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp load_module(module_name) when is_binary(module_name) do
    try do
      # Try to convert to existing atom first
      module_atom = String.to_existing_atom("Elixir.#{module_name}")
      case Code.ensure_loaded(module_atom) do
        {:module, ^module_atom} -> {:ok, module_atom}
        {:error, reason} -> {:error, "Module #{module_name} could not be loaded: #{reason}"}
      end
    rescue
      ArgumentError ->
        # Module atom doesn't exist, try to load it
        module_atom = String.to_atom("Elixir.#{module_name}")
        case Code.ensure_loaded(module_atom) do
          {:module, ^module_atom} -> {:ok, module_atom}
          {:error, :nofile} -> {:error, "Module #{module_name} not found"}
          {:error, reason} -> {:error, "Failed to load module #{module_name}: #{reason}"}
        end
    end
  end
  
  defp prepare_argument_list(args, output_path, context) do
    Enum.map(args, fn arg ->
      prepare_argument(arg, output_path, context)
    end)
  end
  
  defp prepare_argument(arg, output_path, context) when is_binary(arg) do
    cond do
      # Handle atom notation (strings starting with ":")
      String.starts_with?(arg, ":") ->
        String.to_atom(String.trim_leading(arg, ":"))
      
      # Handle special placeholder for output path
      arg == "__OUTPUT_PATH__" ->
        output_path
      
      # Handle data placeholders (e.g., "__DATA.site_name__")
      String.starts_with?(arg, "__DATA.") and String.ends_with?(arg, "__") ->
        data_key = arg
        |> String.trim_leading("__DATA.")
        |> String.trim_trailing("__")
        
        get_data_value(context, data_key)
      
      # Regular string
      true ->
        arg
    end
  end
  
  defp prepare_argument(arg, _output_path, _context) when is_number(arg) or is_boolean(arg) do
    arg
  end
  
  defp prepare_argument(arg, output_path, context) when is_list(arg) do
    # Handle keyword list notation
    Enum.map(arg, fn item ->
      case item do
        %{"opts" => opts} when is_map(opts) ->
          # Convert opts map to keyword list
          opts
          |> Enum.map(fn {key, value} ->
            key_atom = String.to_atom(key)
            prepared_value = prepare_argument(value, output_path, context)
            {key_atom, prepared_value}
          end)
        
        other ->
          prepare_argument(other, output_path, context)
      end
    end)
    |> List.flatten()
  end
  
  defp prepare_argument(arg, output_path, context) when is_map(arg) do
    # Handle opts map directly
    case arg do
      %{"opts" => opts} when is_map(opts) ->
        opts
        |> Enum.map(fn {key, value} ->
          key_atom = String.to_atom(key)
          prepared_value = prepare_argument(value, output_path, context)
          {key_atom, prepared_value}
        end)
      
      _ ->
        arg
    end
  end
  
  defp prepare_argument(arg, _output_path, _context) do
    arg
  end
  
  defp find_function_arity(module, function_atom, prepared_args) do
    # Get all exported functions for this module
    exports = module.__info__(:functions)
    
    # Find all arities for this function
    matching_arities = exports
    |> Enum.filter(fn {name, _arity} -> name == function_atom end)
    |> Enum.map(fn {_name, arity} -> arity end)
    |> Enum.sort()
    
    case matching_arities do
      [] ->
        {:error, "Function #{inspect(function_atom)} not found in module #{inspect(module)}. Available functions: #{inspect(Enum.take(exports, 10))}"}
      
      arities ->
        # Try to find the best matching arity
        preferred_arity = length(prepared_args)
        
        result = cond do
          # Exact match
          preferred_arity in arities ->
            {:ok, preferred_arity, prepared_args}
          
          # If we have too many args, try to find a smaller arity that works
          preferred_arity > Enum.max(arities) ->
            best_arity = Enum.max(arities)
            final_args = Enum.take(prepared_args, best_arity)
            {:ok, best_arity, final_args}
          
          # If we have too few args, try the smallest available arity
          preferred_arity < Enum.min(arities) ->
            best_arity = Enum.min(arities)
            # Pad with nil if needed (though this might cause issues)
            final_args = prepared_args ++ List.duplicate(nil, best_arity - length(prepared_args))
            {:ok, best_arity, final_args}
          
          # Find the closest arity
          true ->
            best_arity = arities
            |> Enum.min_by(fn arity -> abs(arity - preferred_arity) end)
            
            final_args = cond do
              best_arity > length(prepared_args) ->
                prepared_args ++ List.duplicate(nil, best_arity - length(prepared_args))
              best_arity < length(prepared_args) ->
                Enum.take(prepared_args, best_arity)
              true ->
                prepared_args
            end
            
            {:ok, best_arity, final_args}
        end
        
        
        result
    end
  end
  
  defp get_data_value(context, data_key) do
    # Data can be in context[:data], context["data"], or directly in context
    # From the error log, we can see data is directly in context with string keys
    data = context[:data] || context["data"] || context
    
    # Support nested keys like "site.name" -> get_in(data, ["site", "name"])
    keys = String.split(data_key, ".")
    
    # Try string keys first (YAML uses string keys)
    case get_in(data, keys) do
      nil -> 
        # Fallback: try atom keys if string keys don't work
        try do
          atom_keys = Enum.map(keys, &String.to_atom/1)
          get_in(data, atom_keys) || data_key  # Return original if not found
        rescue
          ArgumentError -> data_key  # Return original if atom conversion fails
        end
      value -> 
        value
    end
  end
end