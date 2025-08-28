defmodule Emmer.Processor.FileCopy do
  @moduledoc """
  A processor that copies files to a specified output directory.
  
  This processor simply copies the input file to the configured output directory,
  preserving the filename and optionally creating the directory structure.
  
  ## Configuration
  
  The processor expects the following configuration in folder.yaml:
  
      processors:
        - name: "copy_files"
          module: "Emmer.Processor.FileCopy"
          output_dir: "dist"  # Required - relative to project root or absolute path
          preserve_structure: true  # Optional - preserves relative path structure (default: false)
          filter:
            regex: "\\.(jpg|png|gif|pdf)$"  # Optional - only copy matching files
  
  ## Examples
  
  ### Basic file copy
  ```yaml
  processors:
    - name: "copy_images"
      module: "Emmer.Processor.FileCopy"
      output_dir: "../output/assets"
      filter:
        regex: "\\.(jpg|png|gif)$"
  ```
  
  ### Preserve directory structure
  ```yaml
  processors:
    - name: "copy_all"
      module: "Emmer.Processor.FileCopy"
      output_dir: "dist"
      preserve_structure: true
  ```
  """
  
  use Task
  alias Emmer.Builder.BuildLogger
  
  def start_link(record, processor, context) do
    Task.start_link(__MODULE__, :build, [record, processor, context])
  end
  
  def build(record, processor, context) do
    build_id = context[:build_id] || "unknown"
    
    # Handle both map format (with "path" key) and string format (direct path)
    case record do
      %{"path" => path} -> 
        process_file(path, processor, context, build_id)
      path when is_binary(path) -> 
        process_file(path, processor, context, build_id)
      _ -> 
        root_folder_path = context[:root_folder_path] || context["root_folder_path"] || "."
        BuildLogger.error(root_folder_path, "#{build_id} FileCopy: Invalid record format: #{inspect(record)}")
        {:error, "Invalid record format"}
    end
  end
  
  defp process_file(source_path, processor, context, build_id) do
    root_folder_path = context[:root_folder_path] || context["root_folder_path"] || Path.dirname(source_path)
    
    BuildLogger.debug(root_folder_path, "#{build_id} FileCopy: Processing #{source_path}")
    
    # Validate configuration
    case validate_config(processor) do
      :ok ->
        copy_file(source_path, processor, context, build_id, root_folder_path)
      {:error, reason} ->
        BuildLogger.error(root_folder_path, "#{build_id} FileCopy configuration error: #{reason}")
        {:error, reason}
    end
  end
  
  defp validate_config(processor) do
    cond do
      not Map.has_key?(processor, "output_dir") ->
        {:error, "Missing required 'output_dir' configuration"}
      
      processor["output_dir"] == nil or processor["output_dir"] == "" ->
        {:error, "'output_dir' cannot be empty"}
      
      true ->
        :ok
    end
  end
  
  defp copy_file(source_path, processor, context, build_id, root_folder_path) do
    output_dir = processor["output_dir"]
    preserve_structure = processor["preserve_structure"] || false
    
    # Get the actual project root (where emmer.config.yaml is) from context
    project_root = context[:project_root] || context["project_root"] || 
                   context[:root_folder_path] || context["root_folder_path"] ||
                   root_folder_path
    
    # Make output_dir relative to the project config path (project root)
    absolute_output_dir = if Path.absname(output_dir) == output_dir do
      # Already absolute path, use as-is
      output_dir
    else
      # Relative path, make it relative to the project root (where emmer.config.yaml is)
      Path.join(project_root, output_dir)
    end
    
    # Determine the destination path
    destination_path = if preserve_structure do
      # Preserve the relative directory structure
      main_source_folder = context[:main_source_folder_path] || context["main_source_folder_path"]
      if main_source_folder do
        relative_path = Path.relative_to(source_path, main_source_folder)
        Path.join(absolute_output_dir, relative_path)
      else
        # Fallback to just filename if we can't determine relative structure
        Path.join(absolute_output_dir, Path.basename(source_path))
      end
    else
      # Just copy to output directory with original filename
      Path.join(absolute_output_dir, Path.basename(source_path))
    end
    
    BuildLogger.debug(root_folder_path, "#{build_id} FileCopy: #{source_path} -> #{destination_path}")
    
    # Ensure destination directory exists
    destination_dir = Path.dirname(destination_path)
    case File.mkdir_p(destination_dir) do
      :ok ->
        # Copy the file
        case File.cp(source_path, destination_path) do
          :ok ->
            BuildLogger.info(root_folder_path, "#{build_id} FileCopy: Copied #{Path.basename(source_path)} to #{destination_path}")
            {:ok}
          {:error, reason} ->
            error_msg = "Failed to copy #{source_path} to #{destination_path}: #{reason}"
            BuildLogger.error(root_folder_path, "#{build_id} FileCopy: #{error_msg}")
            {:error, error_msg}
        end
      {:error, reason} ->
        error_msg = "Failed to create directory #{destination_dir}: #{reason}"
        BuildLogger.error(root_folder_path, "#{build_id} FileCopy: #{error_msg}")
        {:error, error_msg}
    end
  end
end