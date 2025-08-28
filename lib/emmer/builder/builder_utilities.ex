defmodule Emmer.Builder.Utilities do

  alias Emmer.Logger.Progress
  alias Emmer.Builder.BuildLogger
  require Logger

  def list_files(source_path) do
    File.ls!(source_path)
  end


  def deep_merge(map1, map2) do
    Map.merge(map1, map2, fn _k, v1, v2 ->
      cond do
        is_map(v1) and is_map(v2) -> deep_merge(v1, v2)
        true -> v2
      end
    end)
  end

  def clear_build_log(root_dir) do
    try do
      File.rm_rf!(Path.join(root_dir, "temp"))
      File.mkdir_p!(Path.join(root_dir, "temp"))
      File.rm_rf!(Path.join(root_dir, "build_log.json"))
      {:ok}
    rescue

      e ->
        {:error, e}
    end
  end

  def add_to_build_log(errors, type, file_path, message) do
    # Create VS Code compatible error format
    # Format: file_path:line:column: type: message
    # For now, we'll use line 1 since we don't have specific line information
    vs_code_error = "#{file_path}:1:1: #{type}: #{message}"

    log = %{
      timestamp: DateTime.utc_now(),
      type: type,
      message: message,
      file_path: file_path,
      vs_code_format: vs_code_error
    }

    [log | errors]
  end

  def generate_error_page(errors, input_file) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Build Error - #{Path.basename(input_file)}</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <script src="https://cdn.tailwindcss.com"></script>
    </head>
    <body class="bg-red-50 min-h-screen">
        <div class="container mx-auto px-4 py-8">
            <div class="max-w-2xl mx-auto">
                <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-6">
                    <h1 class="text-2xl font-bold mb-2">Build Error</h1>
                    <p class="text-sm">File: #{input_file}</p>
                </div>

                <div class="bg-white border border-gray-300 rounded-lg p-6">
                    <h2 class="text-lg font-semibold mb-4">Errors:</h2>
                    <ul class="list-disc list-inside space-y-2">
                        #{Enum.map_join(errors, "", fn error -> "<li class=\"text-red-600\">#{error}</li>" end)}
                    </ul>
                </div>

                <div class="mt-6 text-center">
                    <p class="text-gray-600 text-sm">
                        This page was generated due to build errors. Please fix the issues and rebuild.
                    </p>
                </div>
            </div>
        </div>
    </body>
    </html>
    """
  end

  def load_yaml(source_path, file_name, build_id \\ "Builder") do
    folder_yaml = Path.join(source_path, "#{file_name}.yaml")

    if File.exists?(folder_yaml) do
      BuildLogger.debug(source_path, "#{build_id} Loading yaml file: #{folder_yaml}")
      try do
          {:ok, YamlElixir.read_from_file!(folder_yaml)}
      rescue
        e ->
          BuildLogger.error(source_path, "#{build_id} Failed to parse #{file_name}.yaml: #{e}")
          {:error, e}
      end
    else
      BuildLogger.warn(source_path, "#{build_id} No #{file_name}.yaml found in #{source_path}.")
      {:error, "#{file_name}.yaml does not exist."}
    end
  end

  def module_from_string(module) when is_binary(module) and module != "" do
    aliases = module |> String.split(".")

    module_atom = aliases
    |> Enum.reduce(nil, fn part, acc ->
      Module.concat(acc, part)
    end)
    
    # Check if the module actually exists and is loaded
    case Code.ensure_loaded(module_atom) do
      {:module, ^module_atom} -> module_atom
      {:error, :nofile} -> {:error, "Module '#{module}' not found. Available processors: #{list_available_processors()}"}
      {:error, reason} -> {:error, "Failed to load module '#{module}': #{reason}"}
    end
  end

  def module_from_string(nil) do
    {:error, "Module name cannot be nil"}
  end

  def module_from_string("") do
    {:error, "Module name cannot be empty"}
  end

  def module_from_string(module) do
    {:error, "Invalid module name: #{inspect(module)}"}
  end

  def list_available_processors do
    # List of known processor modules
    available_processors = [
      "Emmer.Processor.YamlLiquidStaticSite",
      "Emmer.Processor.FileCopy", 
      "Emmer.Processor.AssetBuilder",
      "Emmer.Processor.Wait",
      "Emmer.Processor.Image"
    ]
    
    # Filter to only include processors that are actually loaded
    loaded_processors = Enum.filter(available_processors, fn module_name ->
      try do
        module_atom = String.to_existing_atom("Elixir.#{module_name}")
        Code.ensure_loaded?(module_atom)
      rescue
        ArgumentError -> false
      end
    end)
    
    case loaded_processors do
      [] -> Enum.join(available_processors, ", ")
      processors -> Enum.join(processors, ", ")
    end
  end

  def set_logger_level(verbose) do
    verbose = String.to_atom(verbose)

    if verbose in [:emergency, :alert, :critical, :error, :fatal, :warning, :notice, :info, :debug] do
      Logger.configure(level: verbose)
      # Note: Cannot use BuildLogger here as we don't have build_folder context
    else
      # Note: Cannot use BuildLogger here as we don't have build_folder context
      Logger.configure(level: :info)
    end
    :ok
  end
end
