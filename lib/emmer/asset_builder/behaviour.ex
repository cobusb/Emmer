defmodule Emmer.AssetBuilder.Behaviour do
  @moduledoc """
  Behavior for asset builders that can handle different frameworks and build tools.
  
  Asset builders are responsible for taking source assets (CSS, JavaScript, etc.)
  and building them into production-ready assets for static sites.
  
  ## Example Implementation
  
      defmodule MyApp.AssetBuilder.CustomBuilder do
        @behaviour Emmer.AssetBuilder.Behaviour
        
        def build(source_path, output_path, config, context) do
          # Build logic here
          # context contains :root_folder_path and :build_id
          {:ok, ["path/to/built/file.css"]}
        end
        
        def supported_extensions, do: [".css", ".js"] 
        
        def validate_config(config) do
          case Map.has_key?(config, "entry") do
            true -> :ok
            false -> {:error, "Missing 'entry' key"}
          end
        end
        
        def cleanup(temp_files) do
          Enum.each(temp_files, &File.rm/1)
          :ok
        end
      end
  """
  
  @doc """
  Builds assets from source_path and outputs them to output_path.
  
  ## Parameters
  
  * `source_path` - Path to the source directory containing assets to build
  * `output_path` - Path where built assets should be written
  * `config` - Map containing builder-specific configuration
  
  ## Returns
  
  * `{:ok, built_assets}` - List of paths to successfully built asset files
  * `{:error, reason}` - String describing what went wrong
  """
  @callback build(source_path :: String.t(), output_path :: String.t(), config :: map(), context :: map()) :: 
    {:ok, built_assets :: [String.t()]} | {:error, reason :: String.t()}
    
  @doc """
  Returns list of file extensions this builder can handle.
  
  ## Returns
  
  List of file extensions (including the dot), e.g. [".css", ".js", ".ts"]
  """
  @callback supported_extensions() :: [String.t()]
  
  @doc """
  Validates the configuration map before building.
  
  ## Parameters
  
  * `config` - Map containing builder-specific configuration
  
  ## Returns
  
  * `:ok` - Configuration is valid
  * `{:error, reason}` - String describing validation error
  """
  @callback validate_config(config :: map()) :: :ok | {:error, reason :: String.t()}
  
  @doc """
  Cleans up temporary files created during the build process.
  
  This callback is optional. If not implemented, no cleanup will be performed.
  
  ## Parameters
  
  * `temp_files` - List of temporary file paths to clean up
  
  ## Returns
  
  Always returns `:ok`
  """
  @callback cleanup(temp_files :: [String.t()]) :: :ok
  
  @optional_callbacks [cleanup: 1]
end