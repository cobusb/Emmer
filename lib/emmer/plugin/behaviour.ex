defmodule Emmer.Plugin.Behaviour do
  @moduledoc """
  Defines the interface that all Emmer plugins must implement.

  This behaviour provides hooks into the build process, allowing plugins to:
  - Process content before/after templating
  - Load the site data
  - Load templates from a directory
  - Load collections from a directory
  - Transform data and templates
  - Transform collections
  - Transform assets
  - Execute custom logic at various build stages

  ## Required Callbacks

  All plugins must implement:
  - `name/0` - Returns the plugin name
  - `version/0` - Returns the plugin version
  - `description/0` - Returns a description of what the plugin does

  ## Optional Callbacks

  Plugins can optionally implement:
  - `before_build/2` - Called before the build process starts
  - `after_build/2` - Called after the build process completes
  - `load_site_data/2` - Called to load the site data
  - `load_templates/2` - Called to load templates from a directory
  - `load_collections/2` - Called to load collections from a directory
  - `process_collections/4` - Called to process collections
  - `process_content/4` - Called to process content files
  - `process_asset/3` - Called to process static assets

  ## Example Implementation

      defmodule MyPlugin do
        @behaviour Emmer.Plugin.Behaviour

        @impl true
        def name(), do: "my_plugin"
        def version(), do: "1.0.0"
        def description(), do: "My custom plugin"

        @impl true
        def process_content(content, data, file_path) do
          # Process content here
          {:ok, content}
        end
      end
  """

  @type context :: map()
  @type root_path :: String.t()
  @type output_path :: String.t()
  @type file_path :: String.t()
  @type emmer :: Emmer.Emmer.t()
  @type content :: String.t()
  @type data :: map()
  @type collections :: map()

  @doc """
  Returns the plugin name.

  This should be a unique identifier for the plugin.
  """
  @callback name() :: String.t()

  @doc """
  Returns the plugin version.

  Should follow semantic versioning (e.g., "1.0.0").
  """
  @callback version() :: String.t()

  @doc """
  Returns a description of what the plugin does.

  This is used for documentation and debugging purposes.
  """
  @callback description() :: String.t()

  @doc """
  Called before the build process starts.

  This hook is useful for:
  - Setting up plugin state
  - Validating configuration
  - Pre-processing data
  - Initializing external services

  ## Parameters

  - `watcher` - The watcher configuration as it is stored in the Emmer database
  - `context` - Build context containing build options and state

  ## Returns

  - `{:ok, context}` - Success, with potentially modified context
  - `{:error, reason}` - Failure, build will be aborted
  """
  @callback before_build(emmer(), context()) :: {:ok, context()} | {:error, String.t()}

  @doc """
  Called after the build process completes.

  This hook is useful for:
  - Cleanup operations
  - Post-processing generated files
  - Sending notifications
  - Generating reports

  ## Parameters

  - `watcher` - The watcher configuration
  - `context` - Build context containing build results and state

  ## Returns

  - `{:ok, context}` - Success
  - `{:error, reason}` - Failure (logged but doesn't abort build)
  """
  @callback after_build(emmer(), context()) :: {:ok, context()} | {:error, String.t()}

  @doc """
  Called to process content files.

  This hook processes the main content of files (HTML, Markdown, etc.)
  before they are passed to the template engine.

  ## Parameters

  - `content` - The raw content of the file
  - `data` - The data associated with the file (front matter, YAML data, etc.)
  - `file_path` - The path to the file being processed

  ## Returns

  - `{:ok, processed_content}` - Success, with processed content
  - `{:error, reason}` - Failure, file will be skipped
  """
  @callback process_content(content(), data(), file_path()) :: {:ok, content()} | {:error, String.t()}

  @doc """
  Called to process template files.

  This hook processes template files after they have been rendered
  with the final content and data.

  ## Parameters

  - `content` - The rendered template content
  - `data` - The final data used for rendering
  - `file_path` - The path to the template file

  ## Returns

  - `{:ok, processed_content}` - Success, with processed content
  - `{:error, reason}` - Failure, template will be skipped
  """
  @doc """
  Called to process static assets.

  This hook processes static assets like images, CSS, JS, etc.

  ## Parameters

  - `asset_path` - The path to the asset file
  - `output_path` - The path where the processed asset should be written

  ## Returns

  - `{:ok, processed_asset_path}` - Success, with path to processed asset
  - `{:error, reason}` - Failure, asset will be copied as-is
  """
  @callback process_asset(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}

  # Optional callbacks with default implementations
  @optional_callbacks [
    before_build: 2,
    after_build: 2,
    process_asset: 2
  ]

  @doc """
  Default implementation for before_build hook.

  Returns the context unchanged.
  """
  def before_build(_watcher, context), do: {:ok, context}

  @doc """
  Default implementation for after_build hook.

  Returns the context unchanged.
  """
  def after_build(_watcher, context), do: {:ok, context}

  @doc """
  Default implementation for process_asset hook.

  Returns the original asset path unchanged.
  """
  def process_asset(asset_path, _output_path), do: {:ok, asset_path}

  @doc """
  Validates that a module implements the plugin behaviour correctly.

  ## Parameters

  - `module` - The module to validate

  ## Returns

  - `{:ok, plugin_info}` - Success, with plugin metadata
  - `{:error, reason}` - Failure, with reason for validation failure
  """
  def validate_plugin(module) when is_atom(module) do
    try do
      # Check if module implements required callbacks
      required_callbacks = [:name, :version, :description]

      missing_callbacks = Enum.filter(required_callbacks, fn callback ->
        not function_exported?(module, callback, 0)
      end)

      if missing_callbacks == [] do
        # Get plugin metadata
        plugin_info = %{
          module: module,
          name: module.name(),
          version: module.version(),
          description: module.description()
        }

        {:ok, plugin_info}
      else
        {:error, "Missing required callbacks: #{Enum.join(missing_callbacks, ", ")}"}
      end
    rescue
      e ->
        {:error, "Plugin validation failed: #{inspect(e)}"}
    end
  end

  @doc """
  Gets plugin metadata for a given module.

  ## Parameters

  - `module` - The plugin module

  ## Returns

  Plugin metadata map with module, name, version, and description.
  """
  def get_plugin_info(module) when is_atom(module) do
    %{
      module: module,
      name: module.name(),
      version: module.version(),
      description: module.description()
    }
  end
end
