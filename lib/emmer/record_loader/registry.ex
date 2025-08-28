defmodule Emmer.RecordLoader.Registry do
  @moduledoc """
  Registry for discovering available record loaders.
  
  This module provides functionality to list and find record loaders
  that implement the Emmer.RecordLoader.Behaviour.
  """
  
  
  @doc """
  Lists all available record loaders that are currently loaded.
  
  ## Returns
  
  List of maps containing loader information:
  
      [
        %{
          name: "FileLoader",
          module: Emmer.RecordLoader.FileLoader,
          supported_sources: [:file, :directory]
        }
      ]
  """
  def list_available_loaders do
    :code.all_loaded()
    |> Enum.filter(&implements_record_loader_behaviour?/1)
    |> Enum.map(&extract_loader_info/1)
    |> Enum.sort_by(& &1.name)
  end
  
  @doc """
  Finds a specific record loader by name.
  
  ## Parameters
  
  * `name` - String name of the loader module (with or without namespace)
  
  ## Examples
  
      iex> Emmer.RecordLoader.Registry.find_loader("FileLoader")
      {:ok, %{name: "FileLoader", module: Emmer.RecordLoader.FileLoader, ...}}
      
      iex> Emmer.RecordLoader.Registry.find_loader("Emmer.RecordLoader.FileLoader")
      {:ok, %{name: "FileLoader", module: Emmer.RecordLoader.FileLoader, ...}}
  
  ## Returns
  
  * `{:ok, loader_info}` - Map containing loader information
  * `{:error, reason}` - Error if loader not found or invalid
  """
  def find_loader(name) do
    case load_loader_by_name(name) do
      {:ok, module} -> {:ok, extract_loader_info({module, nil})}
      error -> error
    end
  end
  
  @doc """
  Checks if a given module implements the RecordLoader behaviour.
  
  ## Parameters
  
  * `module` - Module atom to check
  
  ## Returns
  
  Boolean indicating if module implements the behaviour
  """
  def implements_behaviour?(module) when is_atom(module) do
    implements_record_loader_behaviour?({module, nil})
  end
  
  @doc """
  Validates a loader module and returns detailed information about what's missing.
  
  ## Parameters
  
  * `module` - Module atom to validate
  
  ## Returns
  
  * `:ok` - Module correctly implements the behaviour
  * `{:error, missing_callbacks}` - List of missing required callbacks
  """
  def validate_implementation(module) when is_atom(module) do
    required_callbacks = [
      {:start_link, 1},
      {:child_spec, 1},
      {:load_records, 2},
      {:read_record, 1},
      {:apply_filter, 2},
      {:count, 1},
      {:validate_config, 1},
      {:supported_sources, 0}
    ]
    
    missing = Enum.reject(required_callbacks, fn {func, arity} ->
      function_exported?(module, func, arity)
    end)
    
    case missing do
      [] -> :ok
      callbacks -> 
        missing_list = Enum.map(callbacks, fn {func, arity} -> "#{func}/#{arity}" end)
        {:error, "Missing required callbacks: #{Enum.join(missing_list, ", ")}"}
    end
  end
  
  defp implements_record_loader_behaviour?({module, _}) do
    try do
      # Check for all required callbacks
      function_exported?(module, :start_link, 1) and
      function_exported?(module, :load_records, 2) and
      function_exported?(module, :read_record, 1) and
      function_exported?(module, :apply_filter, 2) and
      function_exported?(module, :count, 1) and
      function_exported?(module, :validate_config, 1) and
      function_exported?(module, :supported_sources, 0)
    rescue
      _ -> false
    end
  end
  
  defp extract_loader_info({module, _}) do
    module_string = to_string(module)
    name = extract_simple_name(module_string)
    
    supported_sources = try do
      apply(module, :supported_sources, [])
    rescue
      _ -> []
    end
    
    %{
      name: name,
      module: module,
      supported_sources: supported_sources
    }
  end
  
  defp extract_simple_name(module_string) do
    module_string
    |> String.replace("Elixir.", "")
    |> String.split(".")
    |> List.last()
  end
  
  defp load_loader_by_name(name) do
    potential_modules = generate_potential_module_names(name)
    
    Enum.find_value(potential_modules, {:error, :not_found}, fn module_name ->
      try do
        module_atom = String.to_atom("Elixir.#{module_name}")
        case Code.ensure_loaded(module_atom) do
          {:module, ^module_atom} -> 
            if implements_record_loader_behaviour?({module_atom, nil}) do
              {:ok, module_atom}
            else
              nil
            end
          _ -> nil
        end
      rescue
        _ -> nil
      end
    end)
  end
  
  defp generate_potential_module_names(name) do
    # Try various combinations to find the module
    [
      name,                                    # Exact name as given
      "Emmer.RecordLoader.#{name}",           # Standard Emmer namespace
      "RecordLoader.#{name}",                 # Alternative namespace
      extract_last_part(name)                 # Just the last part if full module given
    ]
    |> Enum.uniq()
  end
  
  defp extract_last_part(name) do
    case String.split(name, ".") do
      [_single] -> name  # Single name, return as-is
      parts -> List.last(parts)  # Multiple parts, take the last one
    end
  end
end