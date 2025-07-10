defmodule EmmerNewTaskTest do
  use ExUnit.Case, async: false

  @project "tmp_emmer_project"

  setup do
    File.rm_rf!(@project)
    on_exit(fn -> File.rm_rf!(@project) end)
    :ok
  end

  test "mix emmer.new creates a new project with correct structure and files" do
    Mix.Tasks.Emmer.New.run([@project])
    assert File.dir?(Path.join(@project, "content/home"))
    assert File.dir?(Path.join(@project, "content/about"))
    assert File.dir?(Path.join(@project, "content/blog"))
    assert File.dir?(Path.join(@project, "content/contact"))
    assert File.dir?(Path.join(@project, "templates"))
    assert File.exists?(Path.join(@project, "templates/layout.html"))
    assert File.exists?(Path.join(@project, "templates/header.html"))
    assert File.exists?(Path.join(@project, "templates/footer.html"))
    assert File.exists?(Path.join(@project, ".github/workflows/deploy.yml"))
    assert File.exists?(Path.join(@project, "assets/js/theme-toggle.js"))
    assert File.exists?(Path.join(@project, "assets/css/tailwind.css"))
    # Check deploy workflow for rsync placeholders
    deploy = File.read!(Path.join(@project, ".github/workflows/deploy.yml"))
    assert deploy =~ "DEPLOY_USER"
    assert deploy =~ "rsync"
    # Check DaisyUI import in CSS
    css = File.read!(Path.join(@project, "assets/css/tailwind.css"))
    assert css =~ "daisyui"
    # Check dark/light toggle in layout
    layout = File.read!(Path.join(@project, "templates/layout.html"))
    assert layout =~ "theme-toggle.js"
    # Check header for toggle button
    header = File.read!(Path.join(@project, "templates/header.html"))
    assert header =~ "theme-toggle"
  end
end
