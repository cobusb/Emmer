defmodule SiteEmmerTest do
  use ExUnit.Case, async: true

  @yaml_content """
site:
  name: "Test Church"
  contact:
    email: "test@example.com"
"""

  @html_with_layout """
{% layout "layout.html" %}
<p>Hello World</p>
"""

  @layout_template """
<html><body>{{ content }}</body></html>
"""

  @html_with_include """
{% include "header" %}
<p>Main Content</p>
"""

  @header_template "<header>Header</header>"

  test "load_yaml parses YAML correctly" do
    path = Path.join(System.tmp_dir!(), "test.yaml")
    File.write!(path, @yaml_content)
    result = SiteEmmer.load_yaml(path)
    assert result["site"]["name"] == "Test Church"
    assert result["site"]["contact"]["email"] == "test@example.com"
    File.rm!(path)
  end

  test "extract_layout_and_content extracts layout and content" do
    {layout, content} = SiteEmmer.extract_layout_and_content(@html_with_layout)
    assert layout == "layout"
    assert String.contains?(content, "Hello World")
  end

  test "process_includes replaces includes with template content" do
    templates = %{"header" => "<header>Header</header>"}
    result = SiteEmmer.process_includes(@html_with_include, %{}, templates)
    assert result =~ "<header>Header</header>"
    assert result =~ "Main Content"
  end

  test "render_with_layout renders content inside layout" do
    templates = %{"header" => @header_template}
    context = %{"content" => "<p>Body</p>"}
    html = SiteEmmer.render_with_layout(@layout_template, "<p>Body</p>", context, templates)
    html = if is_list(html), do: Enum.join(html), else: html
    assert html =~ "<body><p>Body</p></body>"
  end

  test "find_files_in_directory matches html and yaml files" do
    tmp = Path.join(System.tmp_dir!(), "emmer_test")
    File.mkdir_p!(tmp)
    File.write!(Path.join(tmp, "index.html"), "<h1>Hi</h1>")
    File.write!(Path.join(tmp, "index.yaml"), "page:\n  title: Test")
    pairs = SiteEmmer.find_files_in_directory(tmp)
    assert Enum.any?(pairs, fn {h, y} ->
      String.ends_with?(h, "index.html") and
      String.ends_with?(y, "index.yaml")
    end)
    File.rm_rf!(tmp)
  end

  test "load_site_data loads site.yaml when it exists" do
    tmp = Path.join(System.tmp_dir!(), "emmer_test")
    File.mkdir_p!(tmp)
    File.write!(Path.join(tmp, "site.yaml"), @yaml_content)
    result = SiteEmmer.load_site_data(tmp)
    assert result["site"]["name"] == "Test Church"
    File.rm_rf!(tmp)
  end

  test "load_site_data returns empty map when site.yaml doesn't exist" do
    tmp = Path.join(System.tmp_dir!(), "emmer_test")
    File.mkdir_p!(tmp)
    result = SiteEmmer.load_site_data(tmp)
    assert result == %{}
    File.rm_rf!(tmp)
  end

  test "generate_sitemap creates valid XML" do
    tmp = Path.join(System.tmp_dir!(), "emmer_test")
    File.mkdir_p!(tmp)

    content_files = [
      {Path.join(tmp, "home/index.html"), nil},
      {Path.join(tmp, "about/index.html"), nil}
    ]

    site_data = %{"site" => %{"url" => "https://example.com"}}

    SiteEmmer.generate_sitemap(content_files, tmp, site_data)

    sitemap_path = Path.join(tmp, "sitemap.xml")
    assert File.exists?(sitemap_path)

    content = File.read!(sitemap_path)
    assert content =~ "<?xml version=\"1.0\""
    assert content =~ "https://example.com/home"
    assert content =~ "https://example.com/about"

    File.rm_rf!(tmp)
  end

  test "copy_static_assets copies static asset directories" do
    src = Path.join(System.tmp_dir!(), "emmer_assets_src")
    out = Path.join(System.tmp_dir!(), "emmer_assets_out")
    File.rm_rf!(src)
    File.rm_rf!(out)
    File.mkdir_p!(Path.join(src, "images"))
    File.mkdir_p!(Path.join(src, "css"))
    File.mkdir_p!(Path.join(src, "js"))
    File.mkdir_p!(Path.join(src, "fonts"))
    File.mkdir_p!(Path.join(src, "downloads"))
    File.write!(Path.join(src, "images/logo.png"), "fakeimg")
    File.write!(Path.join(src, "css/style.css"), "body{}")
    File.write!(Path.join(src, "js/app.js"), "console.log('hi')")
    File.write!(Path.join(src, "fonts/font.ttf"), "fontdata")
    File.write!(Path.join(src, "downloads/file.txt"), "download")
    SiteEmmer.copy_static_assets(src, out, "assets", false)
    assert File.exists?(Path.join(out, "images/logo.png"))
    assert File.exists?(Path.join(out, "css/style.css"))
    assert File.exists?(Path.join(out, "js/app.js"))
    assert File.exists?(Path.join(out, "fonts/font.ttf"))
    assert File.exists?(Path.join(out, "downloads/file.txt"))
    File.rm_rf!(src)
    File.rm_rf!(out)
  end

  test "copy_static_assets copies custom assets_dir if it exists" do
    src = Path.join(System.tmp_dir!(), "emmer_assets_src2")
    out = Path.join(System.tmp_dir!(), "emmer_assets_out2")
    File.rm_rf!(src)
    File.rm_rf!(out)
    File.mkdir_p!(Path.join(src, "assets"))
    File.write!(Path.join(src, "assets/custom.txt"), "custom")
    SiteEmmer.copy_static_assets(src, out, "assets", false)
    assert File.exists?(Path.join(out, "assets/custom.txt"))
    File.rm_rf!(src)
    File.rm_rf!(out)
  end

  test "build_page creates a complex page with layouts, includes, and Liquid templating" do
    tmp = Path.join(System.tmp_dir!(), "emmer_build_test")
    File.rm_rf!(tmp)
    File.mkdir_p!(Path.join(tmp, "content/blog"))
    File.mkdir_p!(Path.join(tmp, "templates"))
    File.mkdir_p!(Path.join(tmp, "dist"))

    # Create complex HTML content with Liquid templating
    html_content = """
    {% layout "main.html" %}

    <h1>{{ page.title }}</h1>
    <p>{{ page.description }}</p>

    {% if page.featured %}
    <div class="featured">
      <h2>Featured: {{ page.featured.title }}</h2>
      <p>{{ page.featured.description }}</p>
    </div>
    {% endif %}

    {% for tag in page.tags %}
    <span class="tag">{{ tag }}</span>
    {% endfor %}

    {% include "sidebar.html" %}

    <div class="content">
      <p>This is the content that should be rendered.</p>
    </div>

    <footer>
      <p>© {{ current_year }} {{ site.name }}</p>
    </footer>
    """

    # Create YAML data
    yaml_content = """
    page:
      title: "My Blog Post"
      description: "This is a test blog post"
      featured:
        title: "Featured Article"
        description: "This is featured content"
      tags:
        - "elixir"
        - "static-site"
        - "emmer"
    """



    # Create main layout template
    layout_template = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>{{ page.title }} - {{ site.name }}</title>
    </head>
    <body>
      {% include "header.html" %}
      <main>
        {{ content }}
      </main>
      {% include "footer.html" %}
    </body>
    </html>
    """

    # Create header include
    header_template = """
    <header>
      <nav>
        <a href="/">Home</a>
        <a href="/blog/">Blog</a>
        <a href="/about/">About</a>
      </nav>
    </header>
    """

    # Create footer include
    footer_template = """
    <footer>
      <p>Built with Emmer</p>
    </footer>
    """

    # Create sidebar include
    sidebar_template = """
    <aside>
      <h3>Recent Posts</h3>
      <ul>
        {% for post in site.recent_posts %}
        <li><a href="{{ post.url }}">{{ post.title }}</a></li>
        {% endfor %}
      </ul>
    </aside>
    """

    # Write test files
    File.write!(Path.join(tmp, "content/blog/index.html"), html_content)
    File.write!(Path.join(tmp, "content/blog/index.yaml"), yaml_content)
    File.write!(Path.join(tmp, "templates/main.html"), layout_template)
    File.write!(Path.join(tmp, "templates/header.html"), header_template)
    File.write!(Path.join(tmp, "templates/footer.html"), footer_template)
    File.write!(Path.join(tmp, "templates/sidebar.html"), sidebar_template)

    # Site data
    site_data = %{
      "site" => %{
        "name" => "Test Site",
        "recent_posts" => [
          %{"title" => "Post 1", "url" => "/post1/"},
          %{"title" => "Post 2", "url" => "/post2/"}
        ]
      }
    }

    # Templates map
    templates = %{
      "main" => layout_template,
      "header" => header_template,
      "footer" => footer_template,
      "sidebar" => sidebar_template
    }

    # Build the page with absolute paths
    SiteEmmer.build_page(
      Path.join(tmp, "content/blog/index.html"),
      Path.join(tmp, "content/blog/index.yaml"),
      site_data,
      templates,
      Path.join(tmp, "dist"),
      false
    )

    # Read the generated output
    output_path = Path.join(tmp, "dist/blog/index.html")
    assert File.exists?(output_path)
    output_content = File.read!(output_path)

    # Verify the output contains expected content
    assert output_content =~ "My Blog Post"
    assert output_content =~ "This is a test blog post"
    assert output_content =~ "Featured Article"
    assert output_content =~ "This is featured content"
    assert output_content =~ "elixir"
    assert output_content =~ "static-site"
    assert output_content =~ "emmer"
    assert output_content =~ "This is the content that should be rendered"
    assert output_content =~ "Test Site"
    assert output_content =~ "Recent Posts"
    assert output_content =~ "Post 1"
    assert output_content =~ "Post 2"
    assert output_content =~ "Built with Emmer"
    assert output_content =~ "Home"
    assert output_content =~ "Blog"
    assert output_content =~ "About"
    assert output_content =~ "© #{Date.utc_today().year}"

    File.rm_rf!(tmp)
  end

  test "build_page handles missing YAML files gracefully" do
    tmp = Path.join(System.tmp_dir!(), "emmer_build_test2")
    File.rm_rf!(tmp)
    File.mkdir_p!(Path.join(tmp, "content/simple"))
    File.mkdir_p!(Path.join(tmp, "templates"))
    File.mkdir_p!(Path.join(tmp, "dist"))

    # Create simple HTML content without YAML
    html_content = """
    <h1>{{ site.name }}</h1>
    <p>Simple page without YAML</p>
    <p>Current year: {{ current_year }}</p>
    """

    File.write!(Path.join(tmp, "content/simple/index.html"), html_content)

    # Build the page with absolute paths
    SiteEmmer.build_page(
      Path.join(tmp, "content/simple/index.html"),
      nil,
      %{"site" => %{"name" => "Simple Site"}},
      %{},
      Path.join(tmp, "dist"),
      false
    )

    # Read the generated output
    output_path = Path.join(tmp, "dist/simple/index.html")
    assert File.exists?(output_path)
    output_content = File.read!(output_path)

    # Verify the output contains expected content
    assert output_content =~ "Simple Site"
    assert output_content =~ "Simple page without YAML"
    assert output_content =~ "Current year: #{Date.utc_today().year}"

    File.rm_rf!(tmp)
  end

  test "build_page handles layout with includes and nested templating" do
    tmp = Path.join(System.tmp_dir!(), "emmer_build_test3")
    File.rm_rf!(tmp)
    File.mkdir_p!(Path.join(tmp, "content/nested"))
    File.mkdir_p!(Path.join(tmp, "templates"))
    File.mkdir_p!(Path.join(tmp, "dist"))

    # Create HTML with layout
    html_content = """
    {% layout "nested.html" %}

    <h1>{{ page.title }}</h1>
    <p>{{ page.content }}</p>
    {% include "widget.html" %}
    """

    # Create YAML data
    yaml_content = """
    page:
      title: "Nested Layout Test"
      content: "This tests nested layouts and includes"
    """

    # Create nested layout
    nested_layout = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>{{ page.title }}</title>
    </head>
    <body>
      {% include "nav.html" %}
      <div class="container">
        {{ content }}
      </div>
      {% include "footer.html" %}
    </body>
    </html>
    """

    # Create navigation include
    nav_template = """
    <nav>
      <a href="/">Home</a>
      <a href="/about/">About</a>
    </nav>
    """

    # Create widget include
    widget_template = """
    <div class="widget">
      <h3>Widget Title</h3>
      <p>Widget content for {{ page.title }}</p>
    </div>
    """

    # Create footer include
    footer_template = """
    <footer>
      <p>Footer for {{ site.name }}</p>
    </footer>
    """

    # Write test files
    File.write!(Path.join(tmp, "content/nested/index.html"), html_content)
    File.write!(Path.join(tmp, "content/nested/index.yaml"), yaml_content)
    File.write!(Path.join(tmp, "templates/nested.html"), nested_layout)
    File.write!(Path.join(tmp, "templates/nav.html"), nav_template)
    File.write!(Path.join(tmp, "templates/widget.html"), widget_template)
    File.write!(Path.join(tmp, "templates/footer.html"), footer_template)

    # Build the page with absolute paths
    SiteEmmer.build_page(
      Path.join(tmp, "content/nested/index.html"),
      Path.join(tmp, "content/nested/index.yaml"),
      %{"site" => %{"name" => "Nested Site"}},
      %{
        "nested" => nested_layout,
        "nav" => nav_template,
        "widget" => widget_template,
        "footer" => footer_template
      },
      Path.join(tmp, "dist"),
      false
    )

    # Read the generated output
    output_path = Path.join(tmp, "dist/nested/index.html")
    assert File.exists?(output_path)
    output_content = File.read!(output_path)

    # Verify the output contains expected content
    assert output_content =~ "Nested Layout Test"
    assert output_content =~ "This tests nested layouts and includes"
    assert output_content =~ "Widget Title"
    assert output_content =~ "Widget content for Nested Layout Test"
    assert output_content =~ "Home"
    assert output_content =~ "About"
    assert output_content =~ "Footer for Nested Site"
    assert output_content =~ "<!DOCTYPE html>"
    assert output_content =~ "<html>"
    assert output_content =~ "<body>"
    assert output_content =~ "<nav>"
    assert output_content =~ "<footer>"

    File.rm_rf!(tmp)
  end

  test "build_page loads YAML data correctly" do
    tmp = Path.join(System.tmp_dir!(), "emmer_yaml_test")
    File.rm_rf!(tmp)
    File.mkdir_p!(Path.join(tmp, "content/test"))
    File.mkdir_p!(Path.join(tmp, "dist"))

    # Create simple HTML with YAML data
    html_content = """
    <h1>{{ page.title }}</h1>
    <p>{{ page.description }}</p>
    """

    yaml_content = """
    page:
      title: "Test Title"
      description: "Test Description"
    """

    File.write!(Path.join(tmp, "content/test/index.html"), html_content)
    File.write!(Path.join(tmp, "content/test/index.yaml"), yaml_content)

    # Build the page with absolute paths
    SiteEmmer.build_page(
      Path.join(tmp, "content/test/index.html"),
      Path.join(tmp, "content/test/index.yaml"),
      %{},
      %{},
      Path.join(tmp, "dist"),
      false
    )

    # Read the generated output
    output_path = Path.join(tmp, "dist/test/index.html")
    assert File.exists?(output_path)
    output_content = File.read!(output_path)

    # Verify YAML data is loaded
    assert output_content =~ "Test Title"
    assert output_content =~ "Test Description"

    File.rm_rf!(tmp)
  end

  test "watcher works with relative root_dir and triggers build" do
    tmp = Path.join(System.tmp_dir!(), "emmer_watch_test")
    File.rm_rf!(tmp)
    File.mkdir_p!(Path.join(tmp, "content"))
    File.mkdir_p!(Path.join(tmp, "templates"))
    File.write!(Path.join(tmp, "content/index.html"), "<h1>Hello</h1>")
    File.write!(Path.join(tmp, "templates/layout.html"), "<html>{{ content }}</html>")

    # Run the watcher in a Task and kill it after a short delay
    task = Task.async(fn ->
      ExUnit.CaptureIO.capture_io(fn ->
        # Should not raise
        SiteEmmer.watch(root_dir: tmp, source_dir: "content", templates_dir: "templates", max_events: 1, verbose: true)
      end)
    end)

    # Wait for watcher to start and do initial build
    :timer.sleep(500)

    # Touch a file to simulate a change (triggers one event)
    File.write!(Path.join(tmp, "content/index.html"), "<h1>Hello again</h1>")
    :timer.sleep(500)

    # Wait for the watcher task to exit and capture output
    output =
      case Task.yield(task, 1000) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        _ -> flunk("Watcher task did not complete in time")
      end

    # Assert output contains expected lines
    assert output =~ "👀 Watching for changes"
    assert output =~ "Press Ctrl+C to stop watching"
    assert output =~ "Built: index.html"
    assert output =~ "File changed:"
  end

  test "watcher does not crash and reports error on build failure" do
    tmp = Path.join(System.tmp_dir!(), "emmer_watch_error_test")
    File.rm_rf!(tmp)
    File.mkdir_p!(Path.join(tmp, "content"))
    File.mkdir_p!(Path.join(tmp, "templates"))
    # Write invalid YAML (not a map)
    File.write!(Path.join(tmp, "content/index.yaml"), "test")
    File.write!(Path.join(tmp, "content/index.html"), "<h1>Test</h1>")
    File.write!(Path.join(tmp, "templates/layout.html"), "<html>{{ content }}</html>")

    # Overwrite with definitely invalid YAML
    invalid_yaml = "page:\n  title: [unclosed bracket"
    File.write!(Path.join(tmp, "content/index.yaml"), invalid_yaml)

    # Let's also test the YAML parsing directly to see if it fails
    yaml_path = Path.join(tmp, "content/index.yaml")
    case SiteEmmer.load_yaml_with_errors(yaml_path) do
      {:ok, _data} -> :ok
      {:error, _error} -> :ok
    end

    output = ExUnit.CaptureIO.capture_io([:stdio, :stderr], fn ->
      SiteEmmer.safe_build(root_dir: tmp)
    end)

    assert output =~ "Build completed with errors"
    assert output =~ "[yaml]"
    assert output =~ "Unfinished flow collection"
    assert output =~ "Continuing to watch for changes"

    File.rm_rf!(tmp)
  end

  test "build with root_dir makes all custom folders relative to root_dir" do
    tmp = Path.join(System.tmp_dir!(), "emmer_custom_folders_test")
    File.rm_rf!(tmp)

    # Create custom folder structure
    File.mkdir_p!(Path.join(tmp, "pages"))
    File.mkdir_p!(Path.join(tmp, "layouts"))
    File.mkdir_p!(Path.join(tmp, "public"))
    File.mkdir_p!(Path.join(tmp, "pages/css"))  # CSS files go in css subfolder within source_dir

    # Create content
    File.write!(Path.join(tmp, "pages/index.html"), "<h1>Custom Content</h1>")
    File.write!(Path.join(tmp, "layouts/main.html"), "<html>{{ content }}</html>")
    File.write!(Path.join(tmp, "pages/css/style.css"), "body { color: red; }")  # CSS in css subfolder

    # Build with custom folders
    SiteEmmer.build([
      root_dir: tmp,
      source_dir: "pages",
      templates_dir: "layouts",
      output_dir: "public",
      assets_dir: "static",
      verbose: true
    ])

    # Verify output was created in custom location
    assert File.exists?(Path.join(tmp, "public/index.html"))
    assert File.exists?(Path.join(tmp, "public/css/style.css"))  # CSS copied to css subfolder

    File.rm_rf!(tmp)
  end

  test "build with root_dir and partial custom folders" do
    tmp = Path.join(System.tmp_dir!(), "emmer_partial_custom_test")
    File.rm_rf!(tmp)

    # Create mixed folder structure (some custom, some default)
    File.mkdir_p!(Path.join(tmp, "content"))  # default
    File.mkdir_p!(Path.join(tmp, "layouts"))  # custom
    File.mkdir_p!(Path.join(tmp, "build"))    # custom
    File.mkdir_p!(Path.join(tmp, "content/css"))   # CSS in css subfolder within source_dir

    # Create content
    File.write!(Path.join(tmp, "content/index.html"), "<h1>Mixed Content</h1>")
    File.write!(Path.join(tmp, "layouts/main.html"), "<html>{{ content }}</html>")
    File.write!(Path.join(tmp, "content/css/style.css"), "body { color: blue; }")  # CSS in css subfolder

    # Build with partial custom folders
    SiteEmmer.build([
      root_dir: tmp,
      templates_dir: "layouts",  # custom
      output_dir: "build",       # custom
      # source_dir and assets_dir use defaults
      verbose: true
    ])

    # Verify output was created in custom location
    assert File.exists?(Path.join(tmp, "build/index.html"))
    assert File.exists?(Path.join(tmp, "build/css/style.css"))  # CSS copied to css subfolder

    File.rm_rf!(tmp)
  end

  test "build with root_dir and only one custom folder" do
    tmp = Path.join(System.tmp_dir!(), "emmer_single_custom_test")
    File.rm_rf!(tmp)

    # Create folder structure with only one custom folder
    File.mkdir_p!(Path.join(tmp, "content"))   # default
    File.mkdir_p!(Path.join(tmp, "templates")) # default
    File.mkdir_p!(Path.join(tmp, "output"))    # custom
    File.mkdir_p!(Path.join(tmp, "content/css"))    # CSS in css subfolder within source_dir

    # Create content
    File.write!(Path.join(tmp, "content/index.html"), "<h1>Single Custom</h1>")
    File.write!(Path.join(tmp, "templates/layout.html"), "<html>{{ content }}</html>")
    File.write!(Path.join(tmp, "content/css/style.css"), "body { color: green; }")  # CSS in css subfolder

    # Build with only output_dir custom
    SiteEmmer.build([
      root_dir: tmp,
      output_dir: "output",  # only custom folder
      verbose: true
    ])

    # Verify output was created in custom location
    assert File.exists?(Path.join(tmp, "output/index.html"))
    assert File.exists?(Path.join(tmp, "output/css/style.css"))  # CSS copied to css subfolder

    File.rm_rf!(tmp)
  end

  test "watch with root_dir and custom folders" do
    tmp = Path.join(System.tmp_dir!(), "emmer_watch_custom_test")
    File.rm_rf!(tmp)

    # Create custom folder structure
    File.mkdir_p!(Path.join(tmp, "pages"))
    File.mkdir_p!(Path.join(tmp, "layouts"))
    File.write!(Path.join(tmp, "pages/index.html"), "<h1>Watch Custom</h1>")
    File.write!(Path.join(tmp, "layouts/main.html"), "<html>{{ content }}</html>")

    # Run watcher with custom folders
    task = Task.async(fn ->
      ExUnit.CaptureIO.capture_io(fn ->
        SiteEmmer.watch([
          root_dir: tmp,
          source_dir: "pages",
          templates_dir: "layouts",
          max_events: 1,
          verbose: true
        ])
      end)
    end)

    # Wait for watcher to start
    :timer.sleep(500)

    # Trigger a file change
    File.write!(Path.join(tmp, "pages/index.html"), "<h1>Updated</h1>")
    :timer.sleep(500)

    # Capture output
    output =
      case Task.yield(task, 1000) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        _ -> flunk("Watcher task did not complete in time")
      end

    # Verify watcher used custom paths
    assert output =~ "pages"
    assert output =~ "layouts"
    assert output =~ "Built: index.html"

    File.rm_rf!(tmp)
  end
end
