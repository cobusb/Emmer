defmodule DebugTest do
  use ExUnit.Case, async: false

  test "debug build process" do
    # Create test structure with unique name
    tmp = Path.join(System.tmp_dir!(), "debug_test_#{:rand.uniform(10000)}")
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

      # Check what files exist before build
      IO.puts("Files before build:")
      IO.puts("content: #{File.ls!("content")}")
      IO.puts("content/home: #{File.ls!("content/home")}")
      IO.puts("templates: #{File.ls!("templates")}")

      # Run build
      result = SiteEmmer.build([
        source_dir: "content",
        output_dir: "dist",
        templates_dir: "templates",
        verbose: true
      ])

      IO.puts("Build result: #{inspect(result)}")

      # Check what files exist after build
      IO.puts("Files after build:")
      if File.exists?("dist") do
        IO.puts("dist: #{File.ls!("dist")}")
      else
        IO.puts("dist directory does not exist")
      end

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
end
