defmodule Emmer.AssetBuilder.TailwindEsbuild do
  @moduledoc """
  Asset builder for Tailwind CSS + esbuild combination.

  This builder handles CSS processing with Tailwind CSS and JavaScript bundling
  with esbuild. It supports TypeScript, modern JavaScript features, and
  Tailwind plugins like DaisyUI.

  ## Configuration

  The builder expects the following configuration:

  * `css_entry` - Path to main CSS file (relative to source_path) **required**
  * `js_entry` - Path to main JavaScript file (relative to source_path) **optional**
  * `content_paths` (optional) - List of paths/globs for Tailwind to scan for classes
  * `plugins` (optional) - List of Tailwind plugins to include
  * `theme` (optional) - Tailwind theme configuration
  * `minify` (optional) - Whether to minify output (default: true)
  * `safelist` (optional) - List of classes to always include in the output CSS

  ## Example Configuration

      %{
        "css_entry" => "styles/main.css",              # Required
        "js_entry" => "js/main.js",                    # Optional - omit if no JavaScript
        "content_paths" => [                            # Optional - custom paths to scan
          "../dist/**/*.html",                          # Scan processed HTML files
          "**/*.{js,ts,jsx,tsx}"                        # Scan source JS files
        ],
        "plugins" => ["daisyui", "@tailwindcss/typography"],
        "theme" => %{
          "colors" => %{
            "primary" => "#3b82f6"
          }
        },
        "minify" => true,
        "safelist" => ["btn-primary", "alert-error"]   # Optional - always include these
      }
  """

  @behaviour Emmer.AssetBuilder.Behaviour

  alias Emmer.Builder.BuildLogger

  def build(source_path, output_path, config, context) do
    build_id = context[:build_id] || "unknown"
    root_folder_path = context[:root_folder_path] || source_path

    BuildLogger.info(root_folder_path, "#{build_id} Building assets with TailwindEsbuild for #{source_path}")

    temp_files = []

    with {:ok, css_files, temp_files} <- build_css(source_path, output_path, config, temp_files, context) do
      # Build JavaScript only if js_entry is provided
      case Map.get(config, "js_entry") do
        nil ->
          cleanup(temp_files, context)
          {:ok, css_files}
        _js_entry ->
          case build_javascript(source_path, output_path, config, temp_files, context) do
            {:ok, js_files, temp_files} ->
              cleanup(temp_files, context)
              {:ok, css_files ++ js_files}
            {:error, reason, temp_files} ->
              cleanup(temp_files, context)
              {:error, reason}
            {:error, reason} ->
              cleanup(temp_files, context)
              {:error, reason}
          end
      end
    else
      {:error, reason, temp_files} ->
        cleanup(temp_files, context)
        {:error, reason}
      {:error, reason} ->
        cleanup(temp_files, context)
        {:error, reason}
    end
  end

  def supported_extensions, do: [".css", ".js", ".ts", ".jsx", ".tsx"]

  def validate_config(config) do
    # Only css_entry is required, js_entry is optional
    required_keys = ["css_entry"]
    missing_keys = Enum.filter(required_keys, &(!Map.has_key?(config, &1)))

    case missing_keys do
      [] -> :ok
      keys -> {:error, "Missing required keys: #{Enum.join(keys, ", ")}"}
    end
  end

  def cleanup(temp_files, context \\ %{}) do
    root_folder_path = context[:root_folder_path] || "."
    build_id = context[:build_id] || "unknown"

    Enum.each(temp_files, fn file ->
      case File.rm(file) do
        :ok -> BuildLogger.debug(root_folder_path, "#{build_id} Cleaned up temp file: #{file}")
        {:error, reason} -> BuildLogger.warn(root_folder_path, "#{build_id} Failed to clean up temp file #{file}: #{reason}")
      end
    end)
    :ok
  end

  defp build_css(source_path, output_path, config, temp_files, context) do
    build_id = context[:build_id] || "unknown"
    root_folder_path = context[:root_folder_path] || source_path

    input_css = Path.join(source_path, config["css_entry"])
    output_css = Path.join(output_path, "main.css")

    if File.exists?(input_css) do
      # Check if there's an existing tailwind.config.js, look in source_path and parent
      existing_config = Path.join(source_path, "tailwind.config.js")
      parent_config = Path.join(Path.dirname(source_path), "tailwind.config.js")
      
      existing_config = cond do
        File.exists?(existing_config) -> existing_config
        File.exists?(parent_config) -> parent_config
        true -> existing_config
      end
      
      {result, tailwind_config_path, content_paths, should_cleanup_config} = if File.exists?(existing_config) do
        # Use existing config file completely - no interference from folder.yaml
        BuildLogger.debug(root_folder_path, "#{build_id} Using existing tailwind.config.js - ignoring folder.yaml Tailwind settings")
        # Use relative path for existing config since we cd to source_path
        relative_config_path = Path.relative_to(existing_config, source_path)
        {:ok, relative_config_path, [], false}  # Empty content_paths since config file handles it
      else
        # Create temporary config as before
        case create_temp_tailwind_config(source_path, config) do
          {:ok, temp_config_path, temp_content_paths} ->
            {:ok, temp_config_path, temp_content_paths, true}
          {:error, reason} ->
            {:error, reason, nil, false}
        end
      end
      
      case result do
        :ok ->
          BuildLogger.debug(root_folder_path, "#{build_id} Tailwind scanning paths: #{inspect(content_paths)}")
          temp_files = if should_cleanup_config, do: [tailwind_config_path | temp_files], else: temp_files
          File.mkdir_p!(Path.dirname(output_css))

          # Make paths relative to the working directory (source_path)
          relative_input_css = Path.relative_to(input_css, source_path)
          relative_output_css = Path.relative_to(output_css, source_path)

          args = build_tailwind_args(relative_input_css, relative_output_css, tailwind_config_path, config)

          case run_command("npx", args, source_path, context) do
            {:ok, _output} ->
              {:ok, [output_css], temp_files}
            {:error, reason} ->
              {:error, "Tailwind CSS build failed: #{reason}", temp_files}
          end
        {:error, reason} ->
          {:error, "Failed to create Tailwind config: #{reason}", temp_files}
      end
    else
      {:error, "CSS entry file not found: #{input_css}", temp_files}
    end
  end

  defp build_javascript(source_path, output_path, config, temp_files, context) do
    input_js = Path.join(source_path, config["js_entry"])
    output_js = Path.join(output_path, "main.js")

    if File.exists?(input_js) do
      File.mkdir_p!(Path.dirname(output_js))

      # Make paths relative to the working directory (source_path)
      relative_input_js = Path.relative_to(input_js, source_path)
      relative_output_js = Path.relative_to(output_js, source_path)

      args = build_esbuild_args(relative_input_js, relative_output_js, config)

      case run_command("npx", args, source_path, context) do
        {:ok, _output} ->
          {:ok, [output_js], temp_files}
        {:error, reason} ->
          {:error, "esbuild failed: #{reason}", temp_files}
      end
    else
      {:error, "JavaScript entry file not found: #{input_js}", temp_files}
    end
  end

  defp create_temp_tailwind_config(source_path, config) do
    # Use custom content paths if provided, otherwise default to scanning source_path
    content_paths = case config["content_paths"] do
      nil ->
        # Default behavior - scan everything in current directory (since we cd to source_path)
        ["**/*.{html,js,ts,jsx,tsx,css}"]
      paths when is_list(paths) ->
        # Custom paths - keep them relative to working directory (source_path)
        Enum.map(paths, fn path ->
          if Path.type(path) == :absolute do
            path
          else
            # Path is relative, keep it relative to the working directory
            path
          end
        end)
      _ ->
        # Invalid format, fall back to default
        ["**/*.{html,js,ts,jsx,tsx,css}"]
    end

    # Build the base config without plugins (since they need special handling)
    tailwind_config = %{
      "content" => content_paths,
      "theme" => config["theme"] || %{}
    }

    # Add daisyui config if provided
    tailwind_config = if config["daisyui"] do
      Map.put(tailwind_config, "daisyui", config["daisyui"])
    else
      tailwind_config
    end

    # Add safelist if provided
    tailwind_config = case config["safelist"] do
      nil -> tailwind_config
      safelist when is_list(safelist) -> Map.put(tailwind_config, "safelist", safelist)
      _ -> tailwind_config
    end

    temp_file = Path.join(System.tmp_dir!(), "tailwind-#{unique_id()}.config.js")

    # Build JavaScript content with plugins as actual require statements
    plugins_js = build_plugins_js(config["plugins"] || [], source_path)
    
    js_content = """
    module.exports = {
      content: #{Jason.encode!(tailwind_config["content"])},
      theme: #{Jason.encode!(tailwind_config["theme"])},
      plugins: [#{plugins_js}]#{if config["daisyui"], do: ",\n      daisyui: #{Jason.encode!(config["daisyui"])}", else: ""}
    };
    """

    case File.write(temp_file, js_content) do
      :ok -> {:ok, temp_file, content_paths}
      {:error, reason} -> {:error, "Failed to write config file: #{reason}"}
    end
  end

  defp build_plugins_js(plugins, source_path) do
    plugins
    |> Enum.map(fn
      plugin when is_binary(plugin) -> 
        # Use absolute path to node_modules to avoid resolution issues from temp directory
        plugin_path = Path.join([source_path, "node_modules", plugin])
        if File.exists?(plugin_path) do
          "require('#{plugin_path}')"
        else
          "require('#{plugin}')" # Fallback to regular require
        end
      %{"name" => name, "config" => plugin_config} ->
        plugin_path = Path.join([source_path, "node_modules", name]) 
        plugin_require = if File.exists?(plugin_path), do: "'#{plugin_path}'", else: "'#{name}'"
        "require(#{plugin_require})(#{Jason.encode!(plugin_config)})"
      %{"name" => name} ->
        plugin_path = Path.join([source_path, "node_modules", name])
        if File.exists?(plugin_path) do
          "require('#{plugin_path}')"
        else
          "require('#{name}')"
        end
    end)
    |> Enum.join(", ")
  end

  defp build_tailwind_args(input_css, output_css, config_path, config) do
    base_args = [
      "tailwindcss",
      "-i", input_css,
      "-o", output_css,
      "--config", config_path
    ]

    if config["minify"] != false do
      base_args ++ ["--minify"]
    else
      base_args
    end
  end

  defp build_esbuild_args(input_js, output_js, config) do
    base_args = [
      "esbuild", input_js,
      "--bundle",
      "--outfile=#{output_js}",
      "--target=es2020",
      "--format=iife"
    ]

    args_with_minify = if config["minify"] != false do
      base_args ++ ["--minify"]
    else
      base_args
    end

    # Add sourcemap for development
    if config["sourcemap"] do
      args_with_minify ++ ["--sourcemap"]
    else
      args_with_minify
    end
  end

  defp run_command(command, args, working_dir, context) do
    root_folder_path = context[:root_folder_path] || working_dir
    build_id = context[:build_id] || "unknown"

    BuildLogger.debug(root_folder_path, "#{build_id} Running: #{command} #{Enum.join(args, " ")} in #{working_dir}")

    case System.cmd(command, args, cd: working_dir, stderr_to_stdout: true) do
      {output, 0} ->
        BuildLogger.debug(root_folder_path, "#{build_id} Command succeeded: #{String.trim(output)}")
        {:ok, output}
      {output, exit_code} ->
        BuildLogger.error(root_folder_path, "#{build_id} Command failed with exit code #{exit_code}: #{String.trim(output)}")
        {:error, "Exit code #{exit_code}: #{String.trim(output)}"}
    end
  rescue
    e in ErlangError ->
      case e.original do
        :enoent ->
          {:error, "Command '#{command}' not found. Make sure Node.js and npm are installed."}
        _ ->
          {:error, "System error: #{Exception.message(e)}"}
      end
  end

  defp unique_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
