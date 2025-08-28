defmodule Emmer.AssetBuilder.ReactVite do
  @moduledoc """
  Asset builder for React applications using Vite.
  
  This builder handles React applications with TypeScript/JavaScript support,
  CSS preprocessing, and modern bundling features through Vite.
  
  ## Configuration
  
  The builder expects the following configuration:
  
  * `entry` - Path to main entry file (relative to source_path)
  * `outDir` (optional) - Output directory name (default: "dist")
  * `base` (optional) - Public base path (default: "/")
  * `minify` (optional) - Whether to minify output (default: true)
  * `sourcemap` (optional) - Generate source maps (default: false)
  
  ## Example Configuration
  
      %{
        "entry" => "src/main.jsx",
        "outDir" => "dist",
        "base" => "/my-app/",
        "minify" => true,
        "sourcemap" => true
      }
  
  ## Requirements
  
  This builder requires:
  
  * Node.js and npm installed
  * Vite and React dependencies in the source directory
  * A valid package.json in the source directory
  """
  
  @behaviour Emmer.AssetBuilder.Behaviour
  
  alias Emmer.Builder.BuildLogger
  
  def build(source_path, output_path, config, context) do
    root_folder_path = context[:root_folder_path] || source_path
    build_id = context[:build_id] || "unknown"
    
    BuildLogger.info(root_folder_path, "#{build_id} Building React app with Vite for #{source_path}")
    
    temp_files = []
    
    with {:ok, _package_json} <- validate_package_json(source_path),
         {:ok, vite_config_path} <- create_temp_vite_config(source_path, output_path, config),
         temp_files <- [vite_config_path | temp_files],
         {:ok, built_files} <- run_vite_build(source_path, vite_config_path, context) do
      cleanup(temp_files, context)
      {:ok, built_files}
    else
      {:error, reason} ->
        cleanup(temp_files, context)
        {:error, reason}
    end
  end
  
  def supported_extensions, do: [".js", ".jsx", ".ts", ".tsx", ".css", ".scss", ".sass", ".less"]
  
  def validate_config(config) do
    case Map.has_key?(config, "entry") do
      true -> 
        # Validate entry file exists would happen at build time
        :ok
      false -> 
        {:error, "Missing required 'entry' key in config"}
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
  
  defp validate_package_json(source_path) do
    package_json_path = Path.join(source_path, "package.json")
    
    case File.exists?(package_json_path) do
      true ->
        case File.read(package_json_path) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, package_json} -> {:ok, package_json}
              {:error, reason} -> {:error, "Invalid package.json: #{reason}"}
            end
          {:error, reason} ->
            {:error, "Cannot read package.json: #{reason}"}
        end
      false ->
        {:error, "package.json not found in #{source_path}"}
    end
  end
  
  defp create_temp_vite_config(source_path, output_path, config) do
    entry_path = Path.join(source_path, config["entry"])
    
    if File.exists?(entry_path) do
      vite_config = build_vite_config_content(source_path, output_path, config)
      temp_file = Path.join(System.tmp_dir!(), "vite-#{unique_id()}.config.js")
      
      case File.write(temp_file, vite_config) do
        :ok -> {:ok, temp_file}
        {:error, reason} -> {:error, "Failed to write Vite config: #{reason}"}
      end
    else
      {:error, "Entry file not found: #{entry_path}"}
    end
  end
  
  defp build_vite_config_content(source_path, output_path, config) do
    entry_path = Path.join(source_path, config["entry"])
    out_dir = config["outDir"] || "dist"
    base = config["base"] || "/"
    minify = if config["minify"] == false, do: false, else: true
    sourcemap = config["sourcemap"] || false
    
    """
    import { defineConfig } from 'vite'
    import react from '@vitejs/plugin-react'
    
    export default defineConfig({
      plugins: [react()],
      base: '#{base}',
      build: {
        outDir: '#{Path.join(output_path, out_dir)}',
        emptyOutDir: true,
        minify: #{minify},
        sourcemap: #{sourcemap},
        rollupOptions: {
          input: '#{entry_path}'
        }
      },
      resolve: {
        alias: {
          '@': '#{source_path}/src'
        }
      }
    })
    """
  end
  
  defp run_vite_build(source_path, vite_config_path, context) do
    root_folder_path = context[:root_folder_path] || source_path
    build_id = context[:build_id] || "unknown"
    
    BuildLogger.debug(root_folder_path, "#{build_id} Running Vite build in #{source_path}")
    
    # First, ensure dependencies are installed
    case ensure_dependencies(source_path, context) do
      :ok ->
        args = ["vite", "build", "--config", vite_config_path]
        
        case run_command("npx", args, source_path, context) do
          {:ok, _output} ->
            collect_built_files(source_path, vite_config_path)
          {:error, reason} ->
            {:error, "Vite build failed: #{reason}"}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp ensure_dependencies(source_path, context) do
    root_folder_path = context[:root_folder_path] || source_path
    build_id = context[:build_id] || "unknown"
    node_modules_path = Path.join(source_path, "node_modules")
    
    case File.exists?(node_modules_path) do
      true -> 
        :ok
      false ->
        BuildLogger.info(root_folder_path, "#{build_id} Installing npm dependencies...")
        case run_command("npm", ["install"], source_path, context) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, "npm install failed: #{reason}"}
        end
    end
  end
  
  defp collect_built_files(_source_path, vite_config_path) do
    # Parse the vite config to find the actual output directory
    case extract_output_dir_from_config(vite_config_path) do
      {:ok, output_dir} ->
        case File.exists?(output_dir) do
          true ->
            built_files = Path.wildcard(Path.join(output_dir, "**/*"))
                         |> Enum.filter(&File.regular?/1)
            {:ok, built_files}
          false ->
            {:error, "Build output directory not found: #{output_dir}"}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp extract_output_dir_from_config(vite_config_path) do
    case File.read(vite_config_path) do
      {:ok, content} ->
        # Simple regex to extract outDir from the config
        case Regex.run(~r/outDir:\s*['"]([^'"]+)['"]/, content) do
          [_, out_dir] -> {:ok, out_dir}
          nil -> {:error, "Could not extract output directory from Vite config"}
        end
      {:error, reason} ->
        {:error, "Could not read Vite config: #{reason}"}
    end
  end
  
  defp run_command(command, args, working_dir, context) do
    root_folder_path = context[:root_folder_path] || working_dir
    build_id = context[:build_id] || "unknown"
    
    BuildLogger.debug(root_folder_path, "#{build_id} Running: #{command} #{Enum.join(args, " ")} in #{working_dir}")
    
    case System.cmd(command, args, cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> 
        BuildLogger.debug(root_folder_path, "#{build_id} Command succeeded")
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