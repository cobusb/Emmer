defmodule IntegrationTest do
  use ExUnit.Case, async: false

  test "complete build process with CSS generation" do
    # Create test project structure
    tmp = Path.join(System.tmp_dir!(), "emmer_integration_test")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    # Create project directories
    File.mkdir_p!(Path.join(tmp, "content"))
    File.mkdir_p!(Path.join(tmp, "templates"))
    File.mkdir_p!(Path.join(tmp, "assets/css"))
    File.mkdir_p!(Path.join(tmp, "dist"))

    # Create content files with Tailwind classes
    File.write!(Path.join(tmp, "content/site.yaml"), """
    site:
      name: "Test Site"
      description: "A test site"
    """)

        File.mkdir_p!(Path.join(tmp, "content/home"))
    File.write!(Path.join(tmp, "content/home/index.html"), """
    {% layout "layout.html" %}

    <div class="container mx-auto px-4">
      <h1 class="text-4xl font-bold text-gray-900">{{ site.name }}</h1>
      <p class="text-lg text-gray-600">{{ site.description }}</p>
      <button class="btn bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded">
        Click me
      </button>
    </div>
    """)

        File.mkdir_p!(Path.join(tmp, "content/about"))
    File.write!(Path.join(tmp, "content/about/index.html"), """
    {% layout "layout.html" %}

    <div class="max-w-4xl mx-auto">
      <h1 class="text-3xl font-bold text-gray-900">About Us</h1>
      <div class="bg-white shadow-lg rounded-lg p-6 mt-6">
        <p class="text-gray-700">This is the about page.</p>
      </div>
    </div>
    """)

    # Create layout template
    File.write!(Path.join(tmp, "templates/layout.html"), """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>{{ page.title | default: site.name }}</title>
        <link href="/css/tailwind.css" rel="stylesheet">
    </head>
    <body class="bg-gray-50">
        <header class="bg-white shadow-sm">
            <nav class="container mx-auto px-4 py-4">
                <a href="/" class="text-xl font-bold text-gray-900">Home</a>
                <a href="/about" class="ml-6 text-gray-600 hover:text-gray-900">About</a>
            </nav>
        </header>

        <main class="py-8">
            {{ content }}
        </main>

        <footer class="bg-gray-800 text-white py-8">
            <div class="container mx-auto px-4 text-center">
                <p>&copy; 2024 {{ site.name }}</p>
            </div>
        </footer>
    </body>
    </html>
    """)

    # Create package.json for CSS generation
    File.write!(Path.join(tmp, "package.json"), """
    {
      "name": "test-site",
      "version": "1.0.0",
      "scripts": {
        "build:css:prod": "tailwindcss --input ./assets/css/input.css --output ./assets/css/tailwind.css --minify"
      },
      "devDependencies": {
        "tailwindcss": "^3.4.0"
      }
    }
    """)

    # Create input CSS file
    File.write!(Path.join(tmp, "assets/css/input.css"), """
    @tailwind base;
    @tailwind components;
    @tailwind utilities;

    @layer components {
      .btn {
        @apply inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md;
      }
    }
    """)

    # Create tailwind config
    File.write!(Path.join(tmp, "tailwind.config.js"), """
    module.exports = {
      content: [
        "./content/**/*.html",
        "./templates/**/*.html"
      ],
      theme: {
        extend: {}
      },
      plugins: []
    }
    """)

    # Change to test directory
    original_dir = File.cwd!()
    File.cd!(tmp)

    try do
      # Run the complete build process
      SiteEmmer.build([
        source_dir: "content",
        output_dir: "dist",
        templates_dir: "templates",
        assets_dir: "assets",
        verbose: false
      ])

      # Verify the build output
      assert File.exists?(Path.join("dist", "home/index.html"))
      assert File.exists?(Path.join("dist", "about/index.html"))
      assert File.exists?(Path.join("dist", "sitemap.xml"))

      # Check that HTML files reference the CSS
      index_html = File.read!(Path.join("dist", "home/index.html"))
      assert index_html =~ "href=\"/css/tailwind.css\""

      about_html = File.read!(Path.join("dist", "about/index.html"))
      assert about_html =~ "href=\"/css/tailwind.css\""

      # Check that Tailwind classes are present in the output
      assert index_html =~ "container mx-auto px-4"
      assert index_html =~ "text-4xl font-bold text-gray-900"
      assert index_html =~ "btn bg-blue-500 hover:bg-blue-600"

      assert about_html =~ "max-w-4xl mx-auto"
      assert about_html =~ "bg-white shadow-lg rounded-lg"

      # Check sitemap
      sitemap = File.read!(Path.join("dist", "sitemap.xml"))
      assert sitemap =~ "<?xml version=\"1.0\""
      assert sitemap =~ "/home"
      assert sitemap =~ "/about"

    after
      File.cd!(original_dir)
      File.rm_rf!(tmp)
    end
  end

  test "build process handles missing Node.js gracefully" do
    # Create minimal test structure with unique name
    tmp = Path.join(System.tmp_dir!(), "emmer_no_node_test_#{:rand.uniform(10000)}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    File.mkdir_p!(Path.join(tmp, "content"))
    File.mkdir_p!(Path.join(tmp, "templates"))
    File.mkdir_p!(Path.join(tmp, "dist"))

    # Create minimal content in a subdirectory
    File.mkdir_p!(Path.join(tmp, "content/home"))
    File.write!(Path.join(tmp, "content/home/index.html"), """
    {% layout "layout.html" %}
    <h1>Hello World</h1>
    """)

    # Ensure templates directory exists and has the layout
    File.mkdir_p!(Path.join(tmp, "templates"))
    File.write!(Path.join(tmp, "templates/layout.html"), """
    <html><body>{{ content }}</body></html>
    """)

    # Change to test directory
    original_dir = File.cwd!()

    try do
      File.cd!(tmp)

      # This should not fail even without Node.js
      SiteEmmer.build([
        source_dir: "content",
        output_dir: "dist",
        templates_dir: "templates",
        verbose: false
      ])

      # Verify basic site generation still works
      assert File.exists?(Path.join("dist", "home/index.html"))

      index_html = File.read!(Path.join("dist", "home/index.html"))
      assert index_html =~ "<h1>Hello World</h1>"

    after
      # Change back to original directory
      File.cd!(original_dir)

      # Clean up test directory
      File.rm_rf!(tmp)
    end
  end

  test "build process with custom CSS classes" do
    # Create test structure
    tmp = Path.join(System.tmp_dir!(), "emmer_custom_css_test")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    File.mkdir_p!(Path.join(tmp, "content"))
    File.mkdir_p!(Path.join(tmp, "templates"))
    File.mkdir_p!(Path.join(tmp, "assets/css"))
    File.mkdir_p!(Path.join(tmp, "dist"))

        # Create content with custom classes
    File.mkdir_p!(Path.join(tmp, "content/home"))
    File.write!(Path.join(tmp, "content/home/index.html"), """
    {% layout "layout.html" %}

    <div class="hero-section">
      <h1 class="hero-title">Welcome</h1>
      <p class="hero-subtitle">This is a custom hero section</p>
    </div>

    <div class="card-container">
      <div class="custom-card">
        <h2>Card Title</h2>
        <p>Card content</p>
      </div>
    </div>
    """)

    File.write!(Path.join(tmp, "templates/layout.html"), """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Test Site</title>
        <link href="/css/tailwind.css" rel="stylesheet">
    </head>
    <body>
        {{ content }}
    </body>
    </html>
    """)

    # Create package.json
    File.write!(Path.join(tmp, "package.json"), """
    {
      "name": "test-site",
      "version": "1.0.0",
      "scripts": {
        "build:css:prod": "tailwindcss --input ./assets/css/input.css --output ./assets/css/tailwind.css --minify"
      },
      "devDependencies": {
        "tailwindcss": "^3.4.0"
      }
    }
    """)

    # Create input CSS with custom components
    File.write!(Path.join(tmp, "assets/css/input.css"), """
    @tailwind base;
    @tailwind components;
    @tailwind utilities;

    @layer components {
      .hero-section {
        @apply bg-gradient-to-r from-blue-600 to-purple-600 text-white py-16 px-4;
      }

      .hero-title {
        @apply text-5xl font-bold mb-4;
      }

      .hero-subtitle {
        @apply text-xl opacity-90;
      }

      .card-container {
        @apply grid md:grid-cols-2 lg:grid-cols-3 gap-6 mt-8;
      }

      .custom-card {
        @apply bg-white rounded-lg shadow-md p-6 border border-gray-200;
      }
    }
    """)

    # Create tailwind config
    File.write!(Path.join(tmp, "tailwind.config.js"), """
    module.exports = {
      content: [
        "./content/**/*.html",
        "./templates/**/*.html"
      ],
      theme: {
        extend: {}
      },
      plugins: []
    }
    """)

    # Change to test directory
    original_dir = File.cwd!()

    try do
      File.cd!(tmp)

      # Run build
      SiteEmmer.build([
        source_dir: "content",
        output_dir: "dist",
        templates_dir: "templates",
        assets_dir: "assets",
        verbose: false
      ])

      # Verify custom classes are in the output
      index_html = File.read!(Path.join("dist", "home/index.html"))
      assert index_html =~ "hero-section"
      assert index_html =~ "hero-title"
      assert index_html =~ "hero-subtitle"
      assert index_html =~ "card-container"
      assert index_html =~ "custom-card"

    after
      # Change back to original directory
      File.cd!(original_dir)

      # Clean up test directory
      File.rm_rf!(tmp)
    end
  end
end
