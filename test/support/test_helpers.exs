defmodule Emmer.TestHelpers do
  @moduledoc """
  Helper functions for tests.
  """
  
  def create_test_yaml_config(folder_path, config \\ %{}) do
    default_config = %{
      "builder" => %{
        "verbose_logging" => "info",
        "source_folder" => "content",
        "ignore_folders" => ["node_modules", ".git", ".DS_Store"]
      },
      "context" => %{
        "site_name" => "Test Site",
        "base_url" => "http://localhost:4000"
      },
      "folder" => %{
        "output_type" => "static"
      },
      "record_loader" => %{
        "type" => "yaml"
      },
      "processors" => [
        %{
          "type" => "markdown_liquid",
          "template_folder" => "templates"
        }
      ]
    }
    
    # For now, just use the default config as a YAML string
    # In production, you'd want to properly merge configs
    yaml_content = """
    builder:
      verbose_logging: info
      source_folder: content
      ignore_folders:
        - node_modules
        - .git
        - .DS_Store
        - dist
        - build
        - _site
        - .next
        - .nuxt
        - coverage
        - tmp
    context:
      site_name: Test Site
      base_url: http://localhost:4000
    folder:
      output_type: static
    record_loader:
      type: yaml
    processors:
      - type: markdown_liquid
        template_folder: templates
    """
    
    config_path = Path.join(folder_path, "emmer.config.yaml")
    File.write!(config_path, yaml_content)
    config_path
  end
  
  def create_test_folder_structure(base_path) do
    # Create directory structure
    dirs = [
      Path.join(base_path, "content"),
      Path.join(base_path, "content/posts"),
      Path.join(base_path, "content/pages"),
      Path.join(base_path, "templates"),
      Path.join(base_path, "assets"),
      Path.join(base_path, "assets/css"),
      Path.join(base_path, "assets/js"),
      Path.join(base_path, "dist")
    ]
    
    Enum.each(dirs, &File.mkdir_p!/1)
    
    # Create sample content files
    create_sample_markdown_file(Path.join(base_path, "content/posts/welcome.md"))
    create_sample_markdown_file(Path.join(base_path, "content/posts/hello.md"))
    create_sample_yaml_file(Path.join(base_path, "content/pages/about.yaml"))
    
    # Create sample template
    create_sample_template(Path.join(base_path, "templates/post.liquid"))
    
    base_path
  end
  
  defp create_sample_markdown_file(path) do
    content = """
    ---
    title: Sample Post
    date: 2024-01-01
    author: Test Author
    ---
    
    # Sample Post
    
    This is a sample markdown post for testing.
    
    ## Section 1
    
    Some content here.
    
    ## Section 2
    
    More content here.
    """
    
    File.write!(path, content)
  end
  
  defp create_sample_yaml_file(path) do
    content = """
    title: About Page
    layout: page
    content: |
      This is the about page content.
      It can span multiple lines.
    metadata:
      description: About our site
      keywords:
        - about
        - information
    """
    
    File.write!(path, content)
  end
  
  defp create_sample_template(path) do
    content = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>{{ title }}</title>
    </head>
    <body>
      <h1>{{ title }}</h1>
      <div class="content">
        {{ content }}
      </div>
    </body>
    </html>
    """
    
    File.write!(path, content)
  end
  
  def wait_for_build_completion(folder_path, timeout \\ 10_000) do
    Phoenix.PubSub.subscribe(Emmer.PubSub, "build_completion:#{folder_path}")
    
    receive do
      {:build_completed, build_id, state} -> {:ok, build_id, state}
    after
      timeout -> {:error, :timeout}
    end
  end
  
  def wait_for_condition(fun, timeout \\ 5_000, interval \\ 100) do
    deadline = System.monotonic_time(:millisecond) + timeout
    
    wait_loop(fun, deadline, interval)
  end
  
  defp wait_loop(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      now = System.monotonic_time(:millisecond)
      if now < deadline do
        Process.sleep(interval)
        wait_loop(fun, deadline, interval)
      else
        {:error, :timeout}
      end
    end
  end
  
  defp deep_merge(map1, map2) when is_map(map1) and is_map(map2) do
    Map.merge(map1, map2, fn _key, v1, v2 ->
      deep_merge(v1, v2)
    end)
  end
  
  defp deep_merge(_v1, v2), do: v2
  
  @doc """
  Starts required supervisors and registries for testing.
  """
  def start_test_supervisors do
    # Start registries individually to handle already started cases
    registries = [
      {Registry, keys: :unique, name: Emmer.Builder.ServerRegistry},
      {Registry, keys: :duplicate, name: Emmer.FileWatcher.Registry},
      {Registry, keys: :unique, name: Emmer.RecordLoader.Registry}
    ]
    
    Enum.each(registries, fn {module, opts} ->
      case apply(module, :start_link, [opts]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        error -> raise "Failed to start registry: #{inspect(error)}"
      end
    end)
    
    # PubSub should already be started by the application
    # Just verify it's running
    case Process.whereis(Emmer.PubSub) do
      nil -> 
        # If not started, start it
        {:ok, _} = Supervisor.start_link([{Phoenix.PubSub, name: Emmer.PubSub}], strategy: :one_for_one)
      _pid -> 
        {:ok, :already_started}
    end
  end
  
  @doc """
  Cleans up all test processes and files.
  """
  def cleanup_test_environment do
    # Stop all test supervisors
    case Process.whereis(Emmer.TestSupervisor) do
      nil -> :ok
      pid -> 
        Supervisor.stop(pid, :normal, 5_000)
    end
    
    # Clean up test directories
    test_dirs = Path.wildcard("/tmp/emmer_test_*")
    Enum.each(test_dirs, &File.rm_rf!/1)
    
    :ok
  end
end