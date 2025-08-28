defmodule Emmer.Processor.YamlLiquidStaticSite do
  @moduledoc """
  A processor that builds static sites using YAML front matter and Liquid templates.

  For each HTML file, this processor:
  1. Looks for matching YAML file (same name, .yaml extension)
  2. Extracts data from the YAML file's data section
  3. Deep merges the data with the context
  4. Reads template file if specified in config.template
  5. Replaces {{ content }} in template with file content
  6. Renders the page using Solid (Liquid template engine)

  ## Array Iteration Support

  This processor supports generating multiple output files from array data in the YAML file.
  Configure `iterate_array` to specify the path to an array in the data, and
  `output_filename_template` to control the output filenames.

  ## Configuration Options

  * `template` - Path to template file (optional)
  * `output_dir` - Output directory (default: "dist")
  * `iterate_array` - Path to array in YAML data for multiple outputs (optional)
  * `output_filename_template` - Template for output filenames when using iterate_array (optional)

  ## Examples

  ### Single Page Generation
  ```yaml
  processors:
    - name: "pages"
      module: "Emmer.Processor.YamlLiquidStaticSite"
      template: "templates/layout.html"
      output_dir: "dist"
      filter:
        regex: "\\.html$"
  ```

  ### Multiple Pages from Array
  ```yaml
  processors:
    - name: "blog_posts"
      module: "Emmer.Processor.YamlLiquidStaticSite"
      template: "templates/post.html"
      output_dir: "dist"
      iterate_array: "posts"
      output_filename_template: "blog/{slug}.html"
      filter:
        regex: "blog\\.html$"
  ```

  With YAML data:
  ```yaml
  data:
    site_name: "My Blog"
    posts:
      - title: "First Post"
        slug: "first-post"
        content: "Hello world"
      - title: "Second Post"
        slug: "second-post"
        content: "Another post"
  ```

  This generates `blog/first-post.html` and `blog/second-post.html`.

  ## Filename Template Placeholders

  * `{index}` - Array index (0-based)
  * `{key}` - Value from array item (supports nested keys like `{user.name}`)
  """
  use Task

  alias Emmer.Builder.BuildLogger
  alias Emmer.Builder.Utilities

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
        BuildLogger.error(root_folder_path, "#{build_id} YamlLiquidStaticSite: Invalid record format")
        {:error, "Invalid record format"}
    end

    BuildLogger.info(root_folder_path, "#{build_id} YamlLiquidStaticSite: Processing #{source_path} with processor #{processor["name"] || "unknown"}")
    BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Processor config: #{inspect(processor)}")

    try do
      case process_file(source_path, processor, context, build_id, root_folder_path) do
        {:ok, output_path} ->
          BuildLogger.info(root_folder_path, "#{build_id} YamlLiquidStaticSite: Generated #{output_path}")
          {:ok}

        {:error, reason} ->
          BuildLogger.error(root_folder_path, "#{build_id} YamlLiquidStaticSite: Failed to process #{source_path}: #{reason}")
          {:error, reason}
      end
    rescue
      error ->
        BuildLogger.error(root_folder_path, "#{build_id} YamlLiquidStaticSite: Exception processing #{source_path}: #{Exception.message(error)}")
        {:error, "Processing exception: #{Exception.message(error)}"}
    end
  end

  defp process_file(source_path, processor, context, build_id, root_folder_path) do
    # Step 1: Look for matching YAML file
    yaml_path = get_yaml_path(source_path)
    file_data = load_yaml_data(yaml_path, build_id, root_folder_path)

    # Step 2 & 3: Extract data and deep merge with context using existing utility
    merged_context = deep_merge_context(context, file_data)

    # Check if array iteration is configured
    case processor["iterate_array"] do
      nil ->
        # Normal processing - single output
        process_single_file(source_path, processor, merged_context, build_id, root_folder_path)

      array_path ->
        # Array iteration - multiple outputs
        process_array_iteration(source_path, processor, merged_context, array_path, build_id, root_folder_path)
    end
  end

  defp process_single_file(source_path, processor, merged_context, build_id, root_folder_path) do
    # Read the HTML file content
    case File.read(source_path) do
      {:ok, html_content} ->
        # Check for template configuration in processor config
        case get_template_content(processor, merged_context, build_id, root_folder_path) do
          {:ok, template_content} ->
            # Replace {{ content }} with HTML content
            final_content = String.replace(template_content, "{{ content }}", html_content)

            # Render with Solid
            render_and_write_single(final_content, merged_context, source_path, processor, build_id, root_folder_path)

          {:error, reason} ->
            {:error, reason}

          :no_template ->
            # No template, render HTML content directly with Solid
            render_and_write_single(html_content, merged_context, source_path, processor, build_id, root_folder_path)
        end

      {:error, reason} ->
        {:error, "Failed to read source file: #{reason}"}
    end
  end

  defp process_array_iteration(source_path, processor, merged_context, array_path, build_id, root_folder_path) do
    # Extract array from context using the specified path
    array_keys = String.split(array_path, ".")
    array_data = get_in(merged_context, array_keys)

    # Debug logging
    BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Array path: #{array_path}")
    BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Array keys: #{inspect(array_keys)}")
    BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Merged context: #{inspect(Map.keys(merged_context))}")
    BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Array data: #{inspect(array_data)}")

    case array_data do
      nil ->
        BuildLogger.warn(root_folder_path, "#{build_id} YamlLiquidStaticSite: Array path '#{array_path}' not found in context")
        {:error, "Array path '#{array_path}' not found"}

      array when is_list(array) ->
        BuildLogger.info(root_folder_path, "#{build_id} YamlLiquidStaticSite: Processing #{length(array)} items from array '#{array_path}'")

        # Process each item in the array
        results = Enum.with_index(array, fn item, index ->
          process_array_item(source_path, processor, merged_context, item, index, build_id, root_folder_path)
        end)

        # Check if all processing succeeded
        case Enum.find(results, fn result -> match?({:error, _}, result) end) do
          nil ->
            output_paths = Enum.map(results, fn {:ok, path} -> path end)
            BuildLogger.info(root_folder_path, "#{build_id} YamlLiquidStaticSite: Generated #{length(output_paths)} files from array")
            {:ok, List.first(output_paths)} # Return first path for consistency
          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        BuildLogger.error(root_folder_path, "#{build_id} YamlLiquidStaticSite: Array path '#{array_path}' points to: #{inspect(array_data)} (not a list)")
        {:error, "Array path '#{array_path}' does not point to a list"}
    end
  end

  defp process_array_item(source_path, processor, base_context, item, index, build_id, root_folder_path) do
    # Merge the array item with the base context
    item_context = deep_merge_context(base_context, %{"item" => item, "index" => index})

    # Read the HTML file content
    case File.read(source_path) do
      {:ok, html_content} ->
        # Check for template configuration
        case get_template_content(processor, item_context, build_id, root_folder_path) do
          {:ok, template_content} ->
            # Replace {{ content }} with HTML content
            final_content = String.replace(template_content, "{{ content }}", html_content)

            # Generate output filename using template
            case generate_output_filename(source_path, processor, item, index, item_context, build_id, root_folder_path) do
              {:ok, output_path} ->
                # Render and write the file
                render_and_write_array_item(final_content, item_context, output_path, build_id, root_folder_path)

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}

          :no_template ->
            # No template, render HTML content directly
            case generate_output_filename(source_path, processor, item, index, item_context, build_id, root_folder_path) do
              {:ok, output_path} ->
                render_and_write_array_item(html_content, item_context, output_path, build_id, root_folder_path)

              {:error, reason} ->
                {:error, reason}
            end
        end

      {:error, reason} ->
        {:error, "Failed to read source file: #{reason}"}
    end
  end

  defp get_yaml_path(html_path) do
    # Replace .html extension with .yaml
    base_path = Path.rootname(html_path)
    "#{base_path}.yaml"
  end

  defp load_yaml_data(yaml_path, build_id, root_folder_path) do
    if File.exists?(yaml_path) do
      BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Loading YAML data from #{yaml_path}")

      case Utilities.load_yaml(Path.dirname(yaml_path), Path.basename(yaml_path, ".yaml"), build_id) do
        {:ok, yaml_data} ->
          # Extract data section if it exists
          Map.get(yaml_data, "data", %{})

        {:error, _reason} ->
          BuildLogger.warn(root_folder_path, "#{build_id} YamlLiquidStaticSite: Failed to load YAML data from #{yaml_path}")
          %{}
      end
    else
      BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: No YAML file found at #{yaml_path}")
      %{}
    end
  end

  defp deep_merge_context(context, file_data) do
    # Convert context to map if it's a keyword list
    context_map = case context do
      context when is_map(context) -> context
      context when is_list(context) -> Enum.into(context, %{})
      _ -> %{}
    end

    # Use existing deep_merge utility - file data takes precedence
    Utilities.deep_merge(context_map, file_data)
  end

  defp get_template_content(processor, context, build_id, root_folder_path) do
    # Check for template in processor configuration
    template_path = processor["template"]

    case template_path do
      nil ->
        :no_template

      path when is_binary(path) ->
        # Resolve template path relative to project root
        project_root = context[:project_root] || context["project_root"] || root_folder_path

        full_template_path = if Path.absname(path) == path do
          # Template path is already absolute
          path
        else
          # Template path is relative, resolve from project root
          Path.join(project_root, path)
        end

        BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Loading template from #{full_template_path}")

        case File.read(full_template_path) do
          {:ok, content} ->
            {:ok, content}

          {:error, reason} ->
            {:error, "Failed to read template file #{full_template_path}: #{reason}"}
        end

      _ ->
        {:error, "Invalid template path configuration"}
    end
  end

  defp generate_output_filename(source_path, processor, item, index, context, build_id, root_folder_path) do
    filename_template = processor["output_filename_template"]

    case filename_template do
      nil ->
        # No template provided, use default naming with index
        base_name = Path.basename(source_path, ".html")
        output_dir = processor["output_dir"] || "dist"
        project_root = context[:project_root] || context["project_root"] || root_folder_path

        output_filename = "#{base_name}_#{index}.html"
        output_path = if Path.absname(output_dir) == output_dir do
          Path.join(output_dir, output_filename)
        else
          Path.join([project_root, output_dir, output_filename])
        end

        {:ok, output_path}

      template when is_binary(template) ->
        # Use template to generate filename
        try do
          # Replace placeholders in the template with item data
          output_filename = replace_filename_placeholders(template, item, index)

          # Resolve relative to project root with output_dir
          project_root = context[:project_root] || context["project_root"] || root_folder_path
          output_dir = processor["output_dir"] || "dist"

          output_path = if Path.absname(output_filename) == output_filename do
            output_filename
          else
            if Path.absname(output_dir) == output_dir do
              Path.join(output_dir, output_filename)
            else
              Path.join([project_root, output_dir, output_filename])
            end
          end

          BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Generated filename: #{output_path}")
          {:ok, output_path}
        rescue
          error ->
            {:error, "Failed to generate output filename: #{Exception.message(error)}"}
        end

      _ ->
        {:error, "Invalid output_filename_template configuration"}
    end
  end

  defp replace_filename_placeholders(template, item, index) do
    # Start with the template
    result = template

    # Replace {index} with the array index
    result = String.replace(result, "{index}", to_string(index))

    # Replace item placeholders like {key} with item["key"]
    # Find all {key} patterns
    placeholders = Regex.scan(~r/\{([^}]+)\}/, result, capture: :all_but_first)

    Enum.reduce(placeholders, result, fn [key], acc ->
      # Get value from item using nested key support (e.g., "user.name")
      value = case String.contains?(key, ".") do
        true ->
          keys = String.split(key, ".")
          get_in(item, keys)
        false ->
          case item do
            map when is_map(map) -> Map.get(map, key)
            _ -> nil
          end
      end

      # Replace the placeholder with the value (or empty string if not found)
      replacement = case value do
        nil -> ""
        val when is_binary(val) -> val
        val -> to_string(val)
      end

      String.replace(acc, "{#{key}}", replacement)
    end)
  end

  defp render_and_write_single(content, context, source_path, processor, build_id, root_folder_path) do
    case render_with_solid(content, context, build_id, root_folder_path) do
      {:ok, rendered_content} ->
        write_output(rendered_content, source_path, processor, context, build_id, root_folder_path)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp render_and_write_array_item(content, context, output_path, build_id, root_folder_path) do
    case render_with_solid(content, context, build_id, root_folder_path) do
      {:ok, rendered_content} ->
        # Ensure output directory exists
        File.mkdir_p!(Path.dirname(output_path))

        case File.write(output_path, rendered_content) do
          :ok ->
            {:ok, output_path}
          {:error, reason} ->
            {:error, "Failed to write output file: #{reason}"}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp render_with_solid(content, context, build_id, root_folder_path) do
    BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Rendering with Solid")

    try do
      # Set up filesystem for includes - use project root as base directory
      project_root = context[:project_root] || context["project_root"] || root_folder_path
      filesystem_instance = Emmer.Builder.EmmerFileSystem.new(project_root, "%s")

      BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: FileSystem root: #{project_root}, pattern: %s")

      # Parse the template with Solid
      case Solid.parse(content) do
        {:ok, template} ->
          # Render the template with context and filesystem (expects {module, instance} tuple)
          case Solid.render(template, context, file_system: {Emmer.Builder.EmmerFileSystem, filesystem_instance}) do
            {:ok, rendered_content} when is_binary(rendered_content) ->
              {:ok, rendered_content}

            {:ok, [rendered_content], _warnings} ->
              # Handle Solid returning [content], warnings format
              {:ok, rendered_content}

            {:ok, rendered_list, _warnings} when is_list(rendered_list) ->
              # Handle case where multiple parts are returned, join them
              rendered_content = Enum.join(rendered_list, "")
              {:ok, rendered_content}

            {:error, reason} ->
              {:error, "Solid render error: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, "Solid parse error: #{inspect(reason)}"}
      end
    rescue
      error ->
        {:error, "Solid processing exception: #{Exception.message(error)}"}
    end
  end

  defp write_output(content, source_path, processor, context, build_id, root_folder_path) do
    # Determine output path based on preserve_structure flag
    output_dir = processor["output_dir"] || "dist"
    preserve_structure = processor["preserve_structure"] != false  # Default to true

    # Get the project root and source folder path from context
    project_root = context[:project_root] || context["project_root"] || root_folder_path
    # For preserve_structure, we want the main source folder path, not the current subfolder path
    source_folder_path = context[:main_source_folder_path] || context["main_source_folder_path"] ||
                        context[:source_folder_path] || context["source_folder_path"] ||
                        root_folder_path

    # Debug logging to understand the paths
    BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: preserve_structure=#{preserve_structure}")
    BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: source_path=#{source_path}")
    BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: source_folder_path=#{source_folder_path}")
    BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: project_root=#{project_root}")

    # Calculate output filename based on preserve_structure setting
    output_filename = if preserve_structure do
      # Calculate relative path from source folder to preserve structure
      case Path.relative_to(source_path, source_folder_path) do
        ^source_path ->
          # If source_path is not relative to source_folder_path, just use filename
          BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Path not relative, using basename")
          Path.basename(source_path)
        rel_path ->
          BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Relative path found: #{rel_path}")
          rel_path
      end
    else
      # Just use the filename without directory structure
      BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: preserve_structure=false, using basename")
      Path.basename(source_path)
    end

    # Build output path
    output_path = if Path.absname(output_dir) == output_dir do
      # output_dir is absolute
      Path.join(output_dir, output_filename)
    else
      # output_dir is relative to project root
      Path.join([project_root, output_dir, output_filename])
    end

    BuildLogger.debug(root_folder_path, "#{build_id} YamlLiquidStaticSite: Writing to #{output_path}")

    # Ensure output directory exists
    File.mkdir_p!(Path.dirname(output_path))

    case File.write(output_path, content) do
      :ok ->
        {:ok, output_path}

      {:error, reason} ->
        {:error, "Failed to write output file: #{reason}"}
    end
  end
end
