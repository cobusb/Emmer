defmodule SiteEmmer do
  @moduledoc """
  A comprehensive static site generator that crawls folders for HTML and YAML files,
  matches them up, and generates content using Solid templating.
  """

  defmodule BuildError do
    @type t :: %__MODULE__{
      file: String.t(),
      line: non_neg_integer(),
      column: non_neg_integer(),
      message: String.t(),
      type: :template | :yaml | :build | :include,
      severity: :error | :warning
    }

    defexception [:file, :line, :column, :message, :type, :severity]

    @impl true
    def message(%__MODULE__{file: file, line: line, column: column, message: message}) do
      "#{file}:#{line}:#{column}: #{message}"
    end
  end

  def build(opts \\ []) do
    root_dir = Keyword.get(opts, :root_dir, File.cwd!())
    source_dir = Keyword.get(opts, :source_dir, "content")
    output_dir = Keyword.get(opts, :output_dir, "dist")
    templates_dir = Keyword.get(opts, :templates_dir, "templates")
    assets_dir = Keyword.get(opts, :assets_dir, "assets")
    verbose = Keyword.get(opts, :verbose, false)
    structured_errors = Keyword.get(opts, :structured_errors, false)

    # Resolve root_dir to absolute path if it's relative
    absolute_root_dir = if Path.relative_to_cwd(root_dir) == root_dir do
      # Path is already absolute
      root_dir
    else
      # Path is relative, expand it
      Path.expand(root_dir)
    end

    # Make paths relative to root_dir if root_dir was explicitly provided
    # This allows users to specify a root_dir and have all other paths be relative to it
    {final_source_dir, final_output_dir, final_templates_dir, final_assets_dir} =
      if Keyword.has_key?(opts, :root_dir) do
        # root_dir was explicitly provided, make ALL paths relative to it
        {
          Path.join(absolute_root_dir, source_dir),
          Path.join(absolute_root_dir, output_dir),
          Path.join(absolute_root_dir, templates_dir),
          Path.join(absolute_root_dir, assets_dir)
        }
      else
        # root_dir was not provided, use paths as-is (backward compatibility)
        {source_dir, output_dir, templates_dir, assets_dir}
      end

    # Change to root directory for the build
    original_dir = File.cwd!()
    File.cd!(absolute_root_dir)

    if verbose do
      IO.puts("🚀 Building static site...")
      IO.puts("📁 Source: #{final_source_dir}")
      IO.puts("📁 Output: #{final_output_dir}")
      IO.puts("📁 Templates: #{final_templates_dir}")
      IO.puts("📁 Assets: #{final_assets_dir}")
    end

    # Ensure output directory exists
    File.mkdir_p!(final_output_dir)

    # Load global site data
    site_data = load_site_data(final_source_dir, verbose)

    # Load templates
    templates = load_templates(final_templates_dir, verbose)

    # Find all content files
    content_files = find_all_content_files(final_source_dir, verbose)

    # Build each page with error collection
    errors = Enum.flat_map(content_files, fn {html_file, yaml_file} ->
      build_page_with_errors(html_file, yaml_file, site_data, templates, final_output_dir, verbose, structured_errors)
    end)

    # Copy static assets
    copy_static_assets(final_source_dir, final_output_dir, final_assets_dir, verbose)

    # Generate sitemap
    generate_sitemap(content_files, final_output_dir, site_data, verbose)

    if verbose do
      IO.puts("✅ Site built successfully!")
    end

    # Return to original directory
    File.cd!(original_dir)

    # Return errors if structured_errors is enabled
    if structured_errors do
      {:ok, errors}
    else
      :ok
    end
  end

  def build_with_errors(opts \\ []) do
    build(Keyword.put(opts, :structured_errors, true))
  end

  def load_site_data(source_dir, verbose \\ false) do
    site_yaml_path = Path.join(source_dir, "site.yaml")

    if File.exists?(site_yaml_path) do
      if verbose, do: IO.puts("📄 Loading site data from #{site_yaml_path}")
      load_yaml(site_yaml_path)
    else
      if verbose, do: IO.puts("⚠️  No site.yaml found, using empty site data")
      %{}
    end
  end

  def load_templates(templates_dir, verbose \\ false) do
    if File.dir?(templates_dir) do
      if verbose, do: IO.puts("📄 Loading templates from #{templates_dir}")

      templates_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".html"))
      |> Enum.map(fn file ->
        name = Path.basename(file, ".html")
        content = File.read!(Path.join(templates_dir, file))
        if verbose, do: IO.puts("  📄 Loaded template: #{name}")
        {name, content}
      end)
      |> Map.new()
    else
      if verbose, do: IO.puts("⚠️  No templates directory found")
      %{}
    end
  end

  def find_all_content_files(source_dir, verbose \\ false) do
    if File.dir?(source_dir) do
      if verbose, do: IO.puts("🔍 Scanning for content files...")

      # First, look for files directly in the source directory
      direct_files = find_files_in_directory(source_dir, verbose)

      # Then, look for files in subdirectories
      subdir_files = source_dir
      |> File.ls!()
      |> Enum.filter(fn item ->
        item_path = Path.join(source_dir, item)
        File.dir?(item_path)
      end)
      |> Enum.flat_map(fn subdir ->
        subdir_path = Path.join(source_dir, subdir)
        find_files_in_directory(subdir_path, verbose)
      end)

      # Combine both
      direct_files ++ subdir_files
    else
      if verbose, do: IO.puts("⚠️  No source directory found")
      []
    end
  end

  def find_files_in_directory(dir_path, verbose \\ false) do
    case File.ls(dir_path) do
      {:ok, files} ->
        html_files = Enum.filter(files, &String.ends_with?(&1, ".html"))
        _yaml_files = Enum.filter(files, &String.ends_with?(&1, ".yaml"))

        Enum.flat_map(html_files, fn html_file ->
          html_path = Path.join(dir_path, html_file)
          base_name = Path.basename(html_file, ".html")

          yaml_file = base_name <> ".yaml"
          yaml_path = Path.join(dir_path, yaml_file)

          yaml_exists = File.exists?(yaml_path)

          if verbose do
            IO.puts("  📄 Found: #{html_file}")
            if yaml_exists, do: IO.puts("    📄 Data: #{yaml_file}")
          end

          [{html_path, if(yaml_exists, do: yaml_path, else: nil)}]
        end)

      {:error, reason} ->
        if verbose, do: IO.puts("❌ Error reading directory #{dir_path}: #{reason}")
        []
    end
  end

  def build_page_with_errors(html_file, yaml_file, site_data, templates, output_dir, verbose \\ false, structured_errors \\ false) do
    errors = []

    # Load page-specific data
    page_data = if yaml_file do
      case load_yaml_with_errors(yaml_file) do
        {:ok, data} -> data
        {:error, error} ->
          errors = [error | errors]
          %{}
      end
    else
      %{}
    end

    # Load HTML content
    html_content = case File.read(html_file) do
      {:ok, content} -> content
      {:error, reason} ->
        error = %BuildError{
          file: html_file,
          line: 1,
          column: 1,
          message: "Failed to read file: #{reason}",
          type: :build,
          severity: :error
        }
        errors = [error | errors]
        ""
    end

    # Extract layout and content
    {layout_name, content, layout_errors} = extract_layout_and_content_with_errors(html_content, html_file)
    errors = errors ++ layout_errors

    # Merge all data - extract page data from YAML
    context = Map.merge(site_data, %{
      "page" => Map.get(page_data, "page", %{}),
      "content" => content,
      "current_year" => Date.utc_today().year
    })

    # Determine output path
    # Extract the subdirectory name from the content path
    # For /tmp/emmer_test/content/simple/index.html, we want "simple/index.html"
    parts = Path.split(html_file)
    # Find the index of "content" in the path
    content_index = Enum.find_index(parts, fn part -> part == "content" end)
    {output_path, relative_path} =
      if content_index do
        # Get everything after "content"
        relative_parts = Enum.drop(parts, content_index + 1)
        relative_path = Path.join(relative_parts)
        {Path.join(output_dir, relative_path), relative_path}
      else
        # Fallback: use the filename
        filename = Path.basename(html_file)
        {Path.join(output_dir, filename), filename}
      end

    # Ensure output directory exists
    output_dir_path = Path.dirname(output_path)
    File.mkdir_p!(output_dir_path)

    # Render with layout if specified
    {rendered_content, render_errors} = if layout_name && Map.has_key?(templates, layout_name) do
      layout_template = Map.get(templates, layout_name)
      render_with_layout_with_errors(layout_template, content, context, templates, html_file)
    else
      render_content_with_errors(content, context, templates, html_file)
    end

    errors = errors ++ render_errors

    # Write output file
    case File.write(output_path, rendered_content) do
      :ok -> :ok
      {:error, reason} ->
        error = %BuildError{
          file: html_file,
          line: 1,
          column: 1,
          message: "Failed to write output file: #{reason}",
          type: :build,
          severity: :error
        }
        errors = [error | errors]
    end

    if verbose do
      IO.puts("✅ Built: #{relative_path}")
    end

    errors
  end

  def build_page(html_file, yaml_file, site_data, templates, output_dir, verbose \\ false) do
    # Load page-specific data
    page_data = if yaml_file, do: load_yaml(yaml_file), else: %{}

    # Load HTML content
    html_content = File.read!(html_file)

    # Extract layout and content
    {layout_name, content} = extract_layout_and_content(html_content)

    # Merge all data - extract page data from YAML
    context = Map.merge(site_data, %{
      "page" => Map.get(page_data, "page", %{}),
      "content" => content,
      "current_year" => Date.utc_today().year
    })

    # Determine output path
    # Extract the subdirectory name from the content path
    # For /tmp/emmer_test/content/simple/index.html, we want "simple/index.html"
    parts = Path.split(html_file)
    # Find the index of "content" in the path
    content_index = Enum.find_index(parts, fn part -> part == "content" end)
    {output_path, relative_path} =
      if content_index do
        # Get everything after "content"
        relative_parts = Enum.drop(parts, content_index + 1)
        relative_path = Path.join(relative_parts)
        {Path.join(output_dir, relative_path), relative_path}
      else
        # Fallback: use the filename
        filename = Path.basename(html_file)
        {Path.join(output_dir, filename), filename}
      end

    # Ensure output directory exists
    output_dir_path = Path.dirname(output_path)
    File.mkdir_p!(output_dir_path)

    # Render with layout if specified
    rendered_content = if layout_name && Map.has_key?(templates, layout_name) do
      layout_template = Map.get(templates, layout_name)
      render_with_layout(layout_template, content, context, templates)
    else
      render_content(content, context, templates)
    end

    # Write output file
    File.write!(output_path, rendered_content)

    if verbose do
      IO.puts("✅ Built: #{relative_path}")
    end
  end

  def extract_layout_and_content_with_errors(html_content, file_path) do
    case Regex.run(~r/{%\s*layout\s+"([^"]+)"\s*%}(.*)/s, html_content) do
      [_, layout_name, content] ->
        # Strip .html extension to match template loading
        clean_layout_name = Path.basename(layout_name, ".html")
        {clean_layout_name, String.trim(content), []}
      nil ->
        {nil, html_content, []}
    end
  end

  def extract_layout_and_content(html_content) do
    case Regex.run(~r/{%\s*layout\s+"([^"]+)"\s*%}(.*)/s, html_content) do
      [_, layout_name, content] ->
        # Strip .html extension to match template loading
        clean_layout_name = Path.basename(layout_name, ".html")
        {clean_layout_name, String.trim(content)}
      nil ->
        {nil, html_content}
    end
  end

  def render_with_layout_with_errors(layout_template, content, context, templates, file_path) do
    # Replace content placeholder in layout
    layout_with_content = String.replace(layout_template, "{{ content }}", content)

    # Render the layout with content
    render_template_with_errors(layout_with_content, context, templates, file_path)
  end

  def render_with_layout(layout_template, content, context, templates) do
    # Replace content placeholder in layout
    layout_with_content = String.replace(layout_template, "{{ content }}", content)

    # Render the layout with content
    render_template(layout_with_content, context, templates)
  end

  def render_content_with_errors(content, context, templates, file_path) do
    render_template_with_errors(content, context, templates, file_path)
  end

  def render_content(content, context, templates) do
    render_template(content, context, templates)
  end

  def render_template_with_errors(template, context, templates, file_path) do
    # Process includes first
    {template_with_includes, include_errors} = process_includes_with_errors(template, context, templates, file_path)

    # Parse and render with Solid
    case Solid.parse(template_with_includes) do
      {:ok, parsed_template} ->
        case Solid.render(parsed_template, context) do
          {:ok, result, errors} ->
            {result, include_errors ++ Enum.map(errors, &solid_error_to_build_error(&1, file_path))}
          {:error, errors, result} ->
            {result, include_errors ++ Enum.map(errors, &solid_error_to_build_error(&1, file_path))}
        end
      {:error, template_error} ->
        {"", include_errors ++ Enum.map(template_error.errors, &solid_parser_error_to_build_error(&1, file_path))}
    end
  end

  def render_template(template, context, templates) do
    # Process includes first
    template_with_includes = process_includes(template, context, templates)

    # Parse and render with Solid
    {:ok, parsed_template} = Solid.parse(template_with_includes)
    Solid.render!(parsed_template, context)
  end

  def process_includes_with_errors(template, context, templates, file_path) do
    errors = []

    template_with_includes = Regex.replace(~r/{%\s*include\s+"([^"]+)"\s*%}/, template, fn match, include_name ->
      # Strip .html extension to match template loading
      clean_include_name = Path.basename(include_name, ".html")
      include_template = Map.get(templates, clean_include_name, "")

      if include_template != "" do
        # Render the include template with the same context
        case Solid.parse(include_template) do
          {:ok, parsed_include} ->
            case Solid.render(parsed_include, context) do
              {:ok, rendered_text, include_errors} ->
                errors = errors ++ Enum.map(include_errors, &solid_error_to_build_error(&1, file_path))
                rendered_text
              {:error, include_errors, rendered_text} ->
                errors = errors ++ Enum.map(include_errors, &solid_error_to_build_error(&1, file_path))
                rendered_text
            end
          {:error, template_error} ->
            errors = errors ++ Enum.map(template_error.errors, &solid_parser_error_to_build_error(&1, file_path))
            ""
        end
      else
        # Include not found
        error = %BuildError{
          file: file_path,
          line: 1,
          column: 1,
          message: "Include template not found: #{include_name}",
          type: :include,
          severity: :error
        }
        errors = [error | errors]
        ""
      end
    end)

    {template_with_includes, errors}
  end

  def process_includes(template, context, templates) do
    Regex.replace(~r/{%\s*include\s+"([^"]+)"\s*%}/, template, fn _, include_name ->
      # Strip .html extension to match template loading
      clean_include_name = Path.basename(include_name, ".html")
      include_template = Map.get(templates, clean_include_name, "")
      if include_template != "" do
        # Render the include template with the same context
        {:ok, parsed_include} = Solid.parse(include_template)
        Solid.render!(parsed_include, context)
      else
        ""
      end
    end)
  end

  def load_yaml_with_errors(path) do
    case File.read(path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, data} -> {:ok, data}
          {:error, error} -> {:error, yaml_error_to_build_error(error, path)}
        end
      {:error, reason} ->
        {:error, %BuildError{
          file: path,
          line: 1,
          column: 1,
          message: "Failed to read YAML file: #{reason}",
          type: :yaml,
          severity: :error
        }}
    end
  end

  def load_yaml(path) do
    path
    |> File.read!()
    |> YamlElixir.read_from_string!()
  end

  defp solid_error_to_build_error(solid_error, file_path) do
    %BuildError{
      file: file_path,
      line: 1,
      column: 1,
      message: Exception.message(solid_error),
      type: :template,
      severity: :error
    }
  end

  defp solid_parser_error_to_build_error(parser_error, file_path) do
    %BuildError{
      file: file_path,
      line: parser_error.meta.line,
      column: parser_error.meta.column,
      message: parser_error.reason,
      type: :template,
      severity: :error
    }
  end

  defp yaml_error_to_build_error(yaml_error, file_path) do
    %BuildError{
      file: file_path,
      line: yaml_error.line || 1,
      column: yaml_error.column || 1,
      message: yaml_error.message,
      type: :yaml,
      severity: :error
    }
  end

  def copy_static_assets(source_dir, output_dir, assets_dir, verbose \\ false) do
    # Ensure output directory exists
    File.mkdir_p!(output_dir)

    static_dirs = ["images", "css", "js", "assets", "fonts", "downloads"]

    Enum.each(static_dirs, fn dir ->
      source_path = Path.join(source_dir, dir)
      output_path = Path.join(output_dir, dir)

      if File.dir?(source_path) do
        File.cp_r!(source_path, output_path)
        if verbose, do: IO.puts("📁 Copied: #{dir}/")
      end
    end)

    # Copy assets directory if it exists
    assets_source = Path.join(source_dir, assets_dir)
    assets_output = Path.join(output_dir, assets_dir)

    if File.dir?(assets_source) do
      File.cp_r!(assets_source, assets_output)
      if verbose, do: IO.puts("📁 Copied: #{assets_dir}/")
    end
  end

  def generate_sitemap(content_files, output_dir, site_data, verbose \\ false) do
    base_url = Map.get(site_data, "site", %{})["url"] || "https://example.com"

    urls = Enum.map(content_files, fn {html_file, _} ->
      # Extract the directory name from the file path
      # For paths like "/tmp/emmer_test/home/index.html", we want "home"
      parts = Path.split(html_file)
      # Find the directory name (second to last part for index.html files)
      dir_name = Enum.at(parts, -2)
      url_path = "/" <> dir_name
      ~s(        <url>\n          <loc>#{base_url}#{url_path}</loc>\n          <lastmod>#{Date.utc_today()}</lastmod>\n        </url>)
    end) |> Enum.join("\n")

    sitemap_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n#{urls}\n</urlset>\n"

    # Ensure output directory exists
    File.mkdir_p!(output_dir)

    sitemap_path = Path.join(output_dir, "sitemap.xml")
    File.write!(sitemap_path, sitemap_content)

    if verbose do
      IO.puts("🗺️  Generated: sitemap.xml")
    end
  end

  def main(args \\ []) do
    {opts, _, _} = OptionParser.parse(args,
      strict: [
        root_dir: :string,
        source_dir: :string,
        output_dir: :string,
        templates_dir: :string,
        assets_dir: :string,
        verbose: :boolean,
        structured_errors: :boolean
      ],
      aliases: [
        r: :root_dir,
        s: :source_dir,
        o: :output_dir,
        t: :templates_dir,
        a: :assets_dir,
        v: :verbose,
        e: :structured_errors
      ]
    )

    build(opts)
  end

  def watch(opts \\ []) do
    root_dir = Keyword.get(opts, :root_dir, File.cwd!())
    source_dir = Keyword.get(opts, :source_dir, "content")
    templates_dir = Keyword.get(opts, :templates_dir, "templates")
    max_events = Keyword.get(opts, :max_events, nil)

    # Resolve root_dir to absolute path if it's relative
    absolute_root_dir = if Path.relative_to_cwd(root_dir) == root_dir do
      # Path is already absolute
      root_dir
    else
      # Path is relative, expand it
      Path.expand(root_dir)
    end

    # Make paths relative to root_dir if root_dir was explicitly provided
    # This allows users to specify a root_dir and have all other paths be relative to it
    {final_source_dir, final_templates_dir} =
      if Keyword.has_key?(opts, :root_dir) do
        # root_dir was explicitly provided, make ALL paths relative to it
        {
          Path.join(absolute_root_dir, source_dir),
          Path.join(absolute_root_dir, templates_dir)
        }
      else
        # root_dir was not provided, use paths as-is (backward compatibility)
        {source_dir, templates_dir}
      end

    IO.puts("👀 Watching for changes in #{final_source_dir} and #{final_templates_dir}")
    IO.puts("Press Ctrl+C to stop watching")

    # Initial build
    build(opts)

    # Watch for changes in the root directory
    {:ok, watcher_pid} = FileSystem.start_link(dirs: [final_source_dir, final_templates_dir])
    FileSystem.subscribe(watcher_pid)

    watch_loop(opts, max_events)
  end

  defp watch_loop(opts, nil) do
    receive do
      {:file_event, _pid, {path, _events}} ->
        if String.ends_with?(path, [".html", ".yaml"]) do
          IO.puts("🔄 File changed: #{path}")
          build(opts)
        end
        watch_loop(opts, nil)

      {:file_event, _pid, :stop} ->
        IO.puts("👋 Stopping file watcher")
    end
  end

  defp watch_loop(opts, 0), do: :ok
  defp watch_loop(opts, n) when is_integer(n) and n > 0 do
    receive do
      {:file_event, _pid, {path, _events}} ->
        if String.ends_with?(path, [".html", ".yaml"]) do
          IO.puts("🔄 File changed: #{path}")
          build(opts)
        end
        watch_loop(opts, n - 1)
      {:file_event, _pid, :stop} ->
        IO.puts("👋 Stopping file watcher")
    end
  end
end

defmodule Mix.Tasks.Emmer.New do
  use Mix.Task
  @shortdoc "Creates a new Emmer static site project with DaisyUI and deploy workflow."

  @moduledoc """
  mix emmer.new <project_name>

  Creates a new Emmer static site project with DaisyUI, dark/light mode, and a deploy workflow (rsync/scp example).
  """

  @impl true
  def run([project_name]) do
    base = Path.expand(project_name)
    File.mkdir_p!(base)
    File.cd!(base, fn ->
      create_structure()
      create_templates()
      create_content()
      create_assets()
      create_github_workflow()
      create_readme(project_name)
    end)
    Mix.shell().info("\nProject '#{project_name}' created!\n\nTo build your site, run this from your Emmer project:\n  ./bin/build ../#{project_name}\n\nOr, if you want to watch for changes and continuaklly build:\n  mix run -e 'SiteEmmer.watch([root_dir: \"../#{project_name}\"])'\n\nYou do NOT need to run mix deps.get in the site directory.\n\nHappy building!\n")
  end

  defp create_structure do
    File.mkdir_p!("content/home")
    File.mkdir_p!("content/about")
    File.mkdir_p!("content/blog")
    File.mkdir_p!("content/contact")
    File.mkdir_p!("templates")
    File.mkdir_p!("assets/js")
    File.mkdir_p!("assets/css")
    File.mkdir_p!(".github/workflows")
  end

  defp create_templates do
    File.write!("templates/layout.html", layout_template())
    File.write!("templates/header.html", header_template())
    File.write!("templates/footer.html", footer_template())
  end

  defp create_content do
    File.write!("content/home/index.html", "{% layout \"layout.html\" %}\n<h1 class=\"text-4xl font-bold mb-4\">Welcome to {{ site.name }}</h1>\n<p>This is your new Emmer site. Edit content/home/index.html to get started.</p>\n")
    File.write!("content/home/index.yaml", "page:\n  title: Home\n")
    File.write!("content/about/index.html", "{% layout \"layout.html\" %}\n<h1 class=\"text-3xl font-bold mb-4\">About Us</h1>\n<p>We are an awesome team using Emmer and DaisyUI!</p>\n")
    File.write!("content/about/index.yaml", "page:\n  title: About Us\n")
    File.write!("content/blog/index.html", "{% layout \"layout.html\" %}\n<h1 class=\"text-3xl font-bold mb-4\">Blog</h1>\n<p>Stay tuned for updates.</p>\n")
    File.write!("content/blog/index.yaml", "page:\n  title: Blog\n")
    File.write!("content/contact/index.html", "{% layout \"layout.html\" %}\n<h1 class=\"text-3xl font-bold mb-4\">Contact Us</h1>\n<p>Email: <a href=\"mailto:info@example.com\" class=\"link\">info@example.com</a></p>\n")
    File.write!("content/contact/index.yaml", "page:\n  title: Contact Us\n")
    File.write!("content/site.yaml", "site:\n  name: \"My Emmer Site\"\n  description: \"A static site generated with Emmer and DaisyUI\"\n")
  end

  defp create_assets do
    File.write!("assets/js/theme-toggle.js", js_toggle())
    File.write!("assets/css/tailwind.css", tailwind_cdn())
  end

  defp create_github_workflow do
    File.write!(".github/workflows/deploy.yml", deploy_workflow())
  end

  defp create_readme(project_name) do
    File.write!("README.md", "# #{project_name}\n\nGenerated with Emmer.\n\nSee .github/workflows/deploy.yml for deployment setup.\n")
  end

  defp layout_template do
    """
<!DOCTYPE html>
<html lang=\"en\" data-theme=\"light\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>{{ page.title }} - {{ site.name }}</title>
  <link href=\"/assets/css/tailwind.css\" rel=\"stylesheet\">
  <script src=\"/assets/js/theme-toggle.js\" defer></script>
</head>
<body class=\"bg-base-100 text-base-content\">
  {% include \"header.html\" %}
  <main class=\"container mx-auto px-4 py-8\">
    {{ content }}
  </main>
  {% include \"footer.html\" %}
</body>
</html>
"""
  end

  defp header_template do
    """
<header class=\"navbar bg-base-200\">
  <div class=\"flex-1\">
    <a class=\"btn btn-ghost text-xl\" href=\"/\">{{ site.name }}</a>
  </div>
  <div class=\"flex-none\">
    <button id=\"theme-toggle\" class=\"btn btn-square btn-ghost\" aria-label=\"Toggle dark mode\">
      <svg id=\"theme-icon\" xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke=\"currentColor\" class=\"w-6 h-6\"></svg>
    </button>
  </div>
</header>
<nav class=\"menu menu-horizontal bg-base-100 rounded-box p-2 mb-4\">
  <a class=\"menu-item btn btn-ghost\" href=\"/\">Home</a>
  <a class=\"menu-item btn btn-ghost\" href=\"/about/\">About</a>
  <a class=\"menu-item btn btn-ghost\" href=\"/blog/\">Blog</a>
  <a class=\"menu-item btn btn-ghost\" href=\"/contact/\">Contact</a>
</nav>
"""
  end

  defp footer_template do
    """
<footer class=\"footer p-4 bg-base-200 text-base-content footer-center\">
  <div>
    <p>© {{ current_year }} {{ site.name }}. Powered by <a href=\"https://github.com/cobusb/Emmer\" class=\"link\">Emmer</a>.</p>
  </div>
</footer>
"""
  end

  defp js_toggle do
    """
// DaisyUI dark/light mode toggle
const themeToggle = document.getElementById('theme-toggle');
const themeIcon = document.getElementById('theme-icon');
const html = document.documentElement;

function setTheme(theme) {
  html.setAttribute('data-theme', theme);
  localStorage.setItem('theme', theme);
  themeIcon.innerHTML = theme === 'dark'
    ? '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m8.66-13.66l-.71.71M4.05 19.95l-.71.71M21 12h-1M4 12H3m16.95 4.95l-.71-.71M6.34 6.34l-.71-.71M12 5a7 7 0 100 14 7 7 0 000-14z" />'
    : '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m8.66-13.66l-.71.71M4.05 19.95l-.71.71M21 12h-1M4 12H3m16.95 4.95l-.71-.71M6.34 6.34l-.71-.71M12 5a7 7 0 100 14 7 7 0 000-14z" />';
}

if (themeToggle) {
  themeToggle.addEventListener('click', () => {
    const current = html.getAttribute('data-theme');
    setTheme(current === 'dark' ? 'light' : 'dark');
  });
  // On load
  setTheme(localStorage.getItem('theme') || 'light');
}
"""
  end

  defp tailwind_cdn do
    """
@import url('https://cdn.jsdelivr.net/npm/daisyui@4.10.2/dist/full.css');
"""
  end

  defp deploy_workflow do
    """
name: Deploy Static Site

on:
  push:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18.4'
          otp-version: '26.0'
      - name: Install dependencies
        run: |
          mix local.hex --force
          mix local.rebar --force
          mix deps.get
      - name: Build site
        run: |
          elixir -e "SiteEmmer.build()"
      - name: Deploy to server (rsync)
        env:
          DEPLOY_USER: ${{ secrets.DEPLOY_USER }}
          DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
          DEPLOY_PATH: ${{ secrets.DEPLOY_PATH }}
        run: |
          rsync -avz --delete dist/ $DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_PATH
"""
  end
end
