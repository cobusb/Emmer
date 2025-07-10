defmodule CssBuilder do
  def build do
    content_dir = "content"
    templates_dir = "templates"
    output_dir = "assets/css"

    # Ensure output directory exists
    File.mkdir_p!(output_dir)

    # Find all HTML files
    html_files = find_html_files(content_dir) ++ find_html_files(templates_dir)

    # Extract Tailwind classes from HTML files
    classes = extract_classes_from_files(html_files)

    # Generate CSS using Tailwind CLI
    generate_css(classes, output_dir)

    IO.puts("✅ CSS built successfully!")
    IO.puts("📁 Output: #{output_dir}/tailwind.css")
    IO.puts("🎨 Classes found: #{length(classes)}")
  end

  def find_html_files(dir) do
    if File.dir?(dir) do
      Path.wildcard(Path.join(dir, "**/*.html"))
    else
      []
    end
  end

  def extract_classes_from_files(files) do
    files
    |> Enum.flat_map(&extract_classes_from_file/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def extract_classes_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        extract_classes_from_content(content)
      {:error, _} ->
        []
    end
  end

  def extract_classes_from_content(content) do
    # Extract class attributes
    class_pattern = ~r/class\s*=\s*["']([^"']+)["']/

    content
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.scan(class_pattern, line) do
        [] -> []
        matches ->
          matches
          |> Enum.map(fn [_, classes] -> classes end)
          |> Enum.flat_map(&String.split(&1, " "))
      end
    end)
    |> Enum.filter(&(&1 != ""))
    |> Enum.uniq()
  end

  def generate_css(classes, output_dir) do
    # Create a temporary HTML file with all the classes
    temp_html = create_temp_html(classes)

    # Use Tailwind CLI to generate CSS
    System.cmd("npx", [
      "tailwindcss",
      "--input", temp_html,
      "--output", Path.join(output_dir, "tailwind.css"),
      "--content", "content/**/*.html",
      "--content", "templates/**/*.html"
    ])

    # Clean up temp file
    File.rm!(temp_html)
  end

  def create_temp_html(classes) do
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>Tailwind Classes</title>
    </head>
    <body>
      <div class=\"#{Enum.join(classes, " ")}\">\n        <!-- All classes used in the project -->\n      </div>
    </body>
    </html>
    """

    temp_file = Path.join(System.tmp_dir!(), "tailwind-classes.html")
    File.write!(temp_file, html_content)
    temp_file
  end
end
