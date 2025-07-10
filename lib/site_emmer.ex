defmodule SiteEmmer do
  @moduledoc """
  A comprehensive static site generator that crawls folders for HTML, YAML, and Markdown files,
  matches them up, and generates content using Solid templating.
  """

  def build(opts \\ []) do
    source_dir = Keyword.get(opts, :source_dir, "content")
    output_dir = Keyword.get(opts, :output_dir, "dist")
    templates_dir = Keyword.get(opts, :templates_dir, "templates")
    assets_dir = Keyword.get(opts, :assets_dir, "assets")
    verbose = Keyword.get(opts, :verbose, false)

    if verbose do
      IO.puts("🚀 Building static site...")
      IO.puts("📁 Source: #{source_dir}")
      IO.puts("📁 Output: #{output_dir}")
      IO.puts("📁 Templates: #{templates_dir}")
      IO.puts("📁 Assets: #{assets_dir}")
    end

    # Ensure output directory exists
    File.mkdir_p!(output_dir)

    # Load global site data
    site_data = load_site_data(source_dir, verbose)

    # Load templates
    templates = load_templates(templates_dir, verbose)

    # Find all content files
    content_files = find_all_content_files(source_dir, verbose)

    # Build each page
    Enum.each(content_files, fn {html_file, yaml_file, markdown_file} ->
      build_page(html_file, yaml_file, markdown_file, site_data, templates, output_dir, verbose)
    end)

    # Copy static assets
    copy_static_assets(source_dir, output_dir, assets_dir, verbose)

    # Generate sitemap
    generate_sitemap(content_files, output_dir, site_data, verbose)

    if verbose do
      IO.puts("✅ Site built successfully!")
    end
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

      source_dir
      |> File.ls!()
      |> Enum.filter(&File.dir?/1)
      |> Enum.flat_map(fn subdir ->
        subdir_path = Path.join(source_dir, subdir)
        find_files_in_directory(subdir_path, verbose)
      end)
    else
      if verbose, do: IO.puts("⚠️  No source directory found")
      []
    end
  end

  def find_files_in_directory(dir_path, verbose \\ false) do
    case File.ls(dir_path) do
      {:ok, files} ->
        html_files = Enum.filter(files, &String.ends_with?(&1, ".html"))
        yaml_files = Enum.filter(files, &String.ends_with?(&1, ".yaml"))
        markdown_files = Enum.filter(files, &String.ends_with?(&1, ".md"))

        Enum.flat_map(html_files, fn html_file ->
          html_path = Path.join(dir_path, html_file)
          base_name = Path.basename(html_file, ".html")

          yaml_file = base_name <> ".yaml"
          yaml_path = Path.join(dir_path, yaml_file)

          markdown_file = base_name <> ".md"
          markdown_path = Path.join(dir_path, markdown_file)

          yaml_exists = File.exists?(yaml_path)
          markdown_exists = File.exists?(markdown_path)

          if verbose do
            IO.puts("  📄 Found: #{html_file}")
            if yaml_exists, do: IO.puts("    📄 Data: #{yaml_file}")
            if markdown_exists, do: IO.puts("    📄 Content: #{markdown_file}")
          end

          [{html_path, if(yaml_exists, do: yaml_path, else: nil), if(markdown_exists, do: markdown_path, else: nil)}]
        end)

      {:error, reason} ->
        if verbose, do: IO.puts("❌ Error reading directory #{dir_path}: #{reason}")
        []
    end
  end

  def build_page(html_file, yaml_file, markdown_file, site_data, templates, output_dir, verbose \\ false) do
    # Load page-specific data
    page_data = if yaml_file, do: load_yaml(yaml_file), else: %{}

    # Load HTML content
    html_content = File.read!(html_file)

    # Load Markdown content if it exists
    markdown_content = if markdown_file do
      File.read!(markdown_file)
    else
      nil
    end

    # Extract layout and content
    {layout_name, content} = extract_layout_and_content(html_content)

    # Merge all data
    context = Map.merge(site_data, %{
      "page" => page_data,
      "content" => content,
      "markdown" => markdown_content,
      "current_year" => Date.utc_today().year
    })

    # Determine output path
    relative_path = Path.relative_to(html_file, "content")
    output_path = Path.join(output_dir, relative_path)

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

  def extract_layout_and_content(html_content) do
    case Regex.run(~r/{%\s*layout\s+"([^"]+)"\s*%}(.*)/s, html_content) do
      [_, layout_name, content] ->
        {layout_name, String.trim(content)}
      nil ->
        {nil, html_content}
    end
  end

  def render_with_layout(layout_template, content, context, templates) do
    # Replace content placeholder in layout
    layout_with_content = String.replace(layout_template, "{{ content }}", content)

    # Render the layout with content
    render_template(layout_with_content, context, templates)
  end

  def render_content(content, context, templates) do
    render_template(content, context, templates)
  end

  def render_template(template, context, templates) do
    # Process includes first
    template_with_includes = process_includes(template, templates)

    # Parse and render with Solid
    {:ok, parsed_template} = Solid.parse(template_with_includes)
    Solid.render!(parsed_template, context)
  end

  def process_includes(template, templates) do
    Regex.replace(~r/{%\s*include\s+"([^"]+)"\s*%}/, template, fn _, include_name ->
      Map.get(templates, include_name, "")
    end)
  end

  def load_yaml(path) do
    path
    |> File.read!()
    |> YamlElixir.read_from_string!()
  end

  def copy_static_assets(source_dir, output_dir, assets_dir, verbose \\ false) do
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

    urls = Enum.map(content_files, fn {html_file, _, _} ->
      parts = Path.split(html_file)
      # Find the last two segments (e.g., ["home", "index.html"])
      last_two = Enum.slice(parts, -2, 2)
      page = hd(last_two)
      url_path = "/" <> page
      ~s(        <url>\n          <loc>#{base_url}#{url_path}</loc>\n          <lastmod>#{Date.utc_today()}</lastmod>\n        </url>)
    end) |> Enum.join("\n")

    sitemap_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n#{urls}\n</urlset>\n"

    sitemap_path = Path.join(output_dir, "sitemap.xml")
    File.write!(sitemap_path, sitemap_content)

    if verbose do
      IO.puts("🗺️  Generated: sitemap.xml")
    end
  end

  def main(args \\ []) do
    {opts, _, _} = OptionParser.parse(args,
      strict: [
        source_dir: :string,
        output_dir: :string,
        templates_dir: :string,
        assets_dir: :string,
        verbose: :boolean
      ],
      aliases: [
        s: :source_dir,
        o: :output_dir,
        t: :templates_dir,
        a: :assets_dir,
        v: :verbose
      ]
    )

    build(opts)
  end

  def watch(opts \\ []) do
    source_dir = Keyword.get(opts, :source_dir, "content")
    templates_dir = Keyword.get(opts, :templates_dir, "templates")

    IO.puts("👀 Watching for changes in #{source_dir} and #{templates_dir}")
    IO.puts("Press Ctrl+C to stop watching")

    # Initial build
    build(opts)

    # Watch for changes
    FileSystem.start_link(dirs: [source_dir, templates_dir])
    FileSystem.subscribe(self())

    watch_loop(opts)
  end

  defp watch_loop(opts) do
    receive do
      {:file_event, _pid, {path, _events}} ->
        if String.ends_with?(path, [".html", ".yaml", ".md"]) do
          IO.puts("🔄 File changed: #{path}")
          build(opts)
        end
        watch_loop(opts)

      {:file_event, _pid, :stop} ->
        IO.puts("👋 Stopping file watcher")
    end
  end
end
