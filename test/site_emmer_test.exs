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
    assert layout == "layout.html"
    assert String.contains?(content, "Hello World")
  end

  test "process_includes replaces includes with template content" do
    templates = %{"header" => @header_template}
    result = SiteEmmer.process_includes(@html_with_include, templates)
    assert String.contains?(result, "<header>Header</header>")
    assert String.contains?(result, "Main Content")
  end

  test "render_with_layout renders content inside layout" do
    templates = %{"header" => @header_template}
    context = %{"content" => "<p>Body</p>"}
    html = SiteEmmer.render_with_layout(@layout_template, "<p>Body</p>", context, templates)
    html = if is_list(html), do: Enum.join(html), else: html
    assert html =~ "<body><p>Body</p></body>"
  end

  test "find_files_in_directory matches html, yaml, and markdown files" do
    tmp = Path.join(System.tmp_dir!(), "emmer_test")
    File.mkdir_p!(tmp)
    File.write!(Path.join(tmp, "index.html"), "<h1>Hi</h1>")
    File.write!(Path.join(tmp, "index.yaml"), "page:\n  title: Test")
    File.write!(Path.join(tmp, "index.md"), "# Test Content")
    pairs = SiteEmmer.find_files_in_directory(tmp)
    assert Enum.any?(pairs, fn {h, y, m} ->
      String.ends_with?(h, "index.html") and
      String.ends_with?(y, "index.yaml") and
      String.ends_with?(m, "index.md")
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
      {Path.join(tmp, "home/index.html"), nil, nil},
      {Path.join(tmp, "about/index.html"), nil, nil}
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
end
