defmodule Emmer.AssetBuilder.Registry do
  @moduledoc """
  Registry for discovering available asset builders.
  
  This module provides functionality to list and find asset builders
  that implement the Emmer.AssetBuilder.Behaviour.
  """
  
  require Logger
  
  @doc """
  Lists all available asset builders that are currently loaded.
  
  ## Returns
  
  List of maps containing builder information:
  
      [
        %{
          name: "TailwindEsbuild",
          module: Emmer.AssetBuilder.TailwindEsbuild,
          supported_extensions: [".css", ".js", ".ts"]
        }
      ]
  """
  def list_available_builders do
    :code.all_loaded()
    |> Enum.filter(&implements_asset_builder_behaviour?/1)
    |> Enum.map(&extract_builder_info/1)
    |> Enum.sort_by(& &1.name)
  end
  
  @doc """
  Finds a specific asset builder by name.
  
  ## Parameters
  
  * `name` - String name of the builder module (with or without namespace)
  
  ## Examples
  
      iex> Emmer.AssetBuilder.Registry.find_builder("TailwindEsbuild")
      {:ok, %{name: "TailwindEsbuild", module: Emmer.AssetBuilder.TailwindEsbuild, ...}}
      
      iex> Emmer.AssetBuilder.Registry.find_builder("Emmer.AssetBuilder.TailwindEsbuild")
      {:ok, %{name: "TailwindEsbuild", module: Emmer.AssetBuilder.TailwindEsbuild, ...}}
  
  ## Returns
  
  * `{:ok, builder_info}` - Map containing builder information
  * `{:error, reason}` - Error if builder not found or invalid
  """
  def find_builder(name) do
    case load_builder_by_name(name) do
      {:ok, module} -> {:ok, extract_builder_info({module, nil})}
      error -> error
    end
  end
  
  @doc """
  Checks if a given module implements the AssetBuilder behaviour.
  
  ## Parameters
  
  * `module` - Module atom to check
  
  ## Returns
  
  Boolean indicating if module implements the behaviour
  """
  def implements_behaviour?(module) when is_atom(module) do
    implements_asset_builder_behaviour?({module, nil})
  end
  
  defp implements_asset_builder_behaviour?({module, _}) do
    try do
      function_exported?(module, :build, 3) and 
      function_exported?(module, :supported_extensions, 0) and
      function_exported?(module, :validate_config, 1)
    rescue
      _ -> false
    end
  end
  
  defp extract_builder_info({module, _}) do
    module_string = to_string(module)
    name = extract_simple_name(module_string)
    
    supported_extensions = try do
      apply(module, :supported_extensions, [])
    rescue
      _ -> []
    end
    
    %{
      name: name,
      module: module,
      supported_extensions: supported_extensions
    }
  end
  
  defp extract_simple_name(module_string) do
    module_string
    |> String.replace("Elixir.", "")
    |> String.split(".")
    |> List.last()
  end
  
  defp load_builder_by_name(name) do
    potential_modules = generate_potential_module_names(name)
    
    Enum.find_value(potential_modules, {:error, :not_found}, fn module_name ->
      try do
        module_atom = String.to_atom("Elixir.#{module_name}")
        case Code.ensure_loaded(module_atom) do
          {:module, ^module_atom} -> 
            if implements_asset_builder_behaviour?({module_atom, nil}) do
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
      "Emmer.AssetBuilder.#{name}",           # Standard Emmer namespace
      "AssetBuilder.#{name}",                 # Alternative namespace
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