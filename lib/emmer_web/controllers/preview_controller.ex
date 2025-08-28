defmodule EmmerWeb.PreviewController do
  use EmmerWeb, :controller

  plug EmmerWeb.PreviewFabPlug

  def show(conn, %{"emmer_id" => emmer_id} = params) do
    file = params["file"]
    emmer = Emmer.Repo.get(Emmer.EmmerRoot, emmer_id)

    if is_nil(emmer) do
      conn
      |> put_status(:not_found)
      |> text("Emmer not found")
    else
      root_dir = emmer.path_to_config
      default_file = file || "index.html"
      relative_path = Path.join([root_dir, emmer.browse_dir, default_file])

      if File.exists?(relative_path) do
        content = File.read!(relative_path)

        # Rewrite links and assets for preview
        modified_content = rewrite_content_for_preview(content, emmer_id, emmer)

        # Generate FAB menu HTML
        fab_html = EmmerWeb.PreviewFabPlug.generate_fab_menu(emmer)

        # Render the independent preview page
        conn
        |> put_resp_content_type("text/html")
        |> render("preview.html",
          emmer: emmer,
          file: file || "index.html",
          content: modified_content,
          emmer_id: emmer_id,
          fab_html: fab_html
        )
      else
        conn
        |> put_status(:not_found)
        |> text("File not found")
      end
    end
  end

  def asset(conn, %{"emmer_id" => emmer_id, "file" => file}) do
    emmer = Emmer.Repo.get(Emmer.EmmerRoot, emmer_id)

    if is_nil(emmer) do
      conn
      |> put_status(:not_found)
      |> text("Watcher not found")
    else
      # Only serve assets from the output directory (built assets)
      # Remove leading slash from file to ensure proper path joining
      clean_file = String.trim_leading(file, "/")
      output_path = Path.join([emmer.path_to_config, emmer.browse_dir, clean_file])

      if File.exists?(output_path) do
        serve_asset(conn, output_path)
      else
        conn
        |> put_status(:not_found)
        |> text("Asset not found")
      end
    end
  end

  def asset(conn, %{"emmer_id" => _emmer_id}) do
    # Handle case where file parameter is missing
    conn
    |> put_status(:bad_request)
    |> text("Missing file parameter")
  end

  def file_explorer(conn, %{"emmer_id" => emmer_id}) do
    emmer = Emmer.Repo.get(Emmer.EmmerRoot, emmer_id)

    if is_nil(emmer) do
      conn
      |> put_status(:not_found)
      |> json(%{error: "Emmer not found"})
    else
      root_path = Path.join([emmer.path_to_config, emmer.browse_dir])
      file_structure = build_file_structure(root_path, root_path)

      conn
      |> json(%{
        files: file_structure,
        root_path: root_path,
        browse_dir: emmer.browse_dir
      })
    end
  end

  # Make this public for testability
  def rewrite_content_for_preview(content, emmer_id, emmer) do
    content
    |> rewrite_links(emmer_id)
    |> rewrite_assets(emmer_id)
  end

  def rewrite_links(content, watcher_id) do
    # Handle both .html files and absolute paths like /about/
    link_pattern = ~r/href=["']([^"']*)["']/i
    Regex.replace(link_pattern, content, fn _full, link_path ->
      if is_relative_link?(link_path) and is_html_link?(link_path) do
        file_path = convert_path_to_file(link_path)
        "href=\"/preview/#{watcher_id}?file=#{file_path}\""
      else
        "href=\"#{link_path}\""
      end
    end, global: true)
  end

  defp rewrite_assets(content, watcher_id) do
    # Rewrite relative asset paths to use the asset proxy
    # Handle img src, link href (for CSS), script src
    content
    |> rewrite_img_src(watcher_id)
    |> rewrite_css_links(watcher_id)
    |> rewrite_script_src(watcher_id)
    |> rewrite_tailwind_bg_urls(watcher_id)
  end

  defp rewrite_img_src(content, watcher_id) do
    img_pattern = ~r/src=["']([^"']*\.(?:jpg|jpeg|png|gif|svg|webp))["']/i
    Regex.replace(img_pattern, content, fn _full, img_path ->
      if is_relative_link?(img_path) do
        "src=\"/preview/#{watcher_id}/asset?file=#{img_path}\""
      else
        "src=\"#{img_path}\""
      end
    end, global: true)
  end

  defp rewrite_css_links(content, watcher_id) do
    css_pattern = ~r/href=["']([^"']*\.css)["']/i
    result = Regex.replace(css_pattern, content, fn _full, css_path ->
      if is_relative_link?(css_path) do
        rewritten = "href=\"/preview/#{watcher_id}/asset?file=#{css_path}\""
        rewritten
      else
        "href=\"#{css_path}\""
      end
    end, global: true)

    if content != result do
      IO.puts("CSS rewriting occurred")
    else
      IO.puts("No CSS rewriting occurred - no CSS links found")
    end

    result
  end

  defp rewrite_script_src(content, watcher_id) do
    script_pattern = ~r/src=["']([^"']*\.js)["']/i
    Regex.replace(script_pattern, content, fn _full, script_path ->
      if is_relative_link?(script_path) do
        "src=\"/preview/#{watcher_id}/asset?file=#{script_path}\""
      else
        "src=\"#{script_path}\""
      end
    end, global: true)
  end

  defp rewrite_tailwind_bg_urls(content, watcher_id) do
    # Handle various Tailwind classes that can contain file paths
    content
    |> rewrite_bg_url_patterns(watcher_id)
    |> rewrite_gradient_patterns(watcher_id)
    |> rewrite_mask_patterns(watcher_id)
    |> rewrite_clip_path_patterns(watcher_id)
  end

  defp rewrite_bg_url_patterns(content, watcher_id) do
    # Handle Tailwind background image URLs like bg-[url('path/to/image.jpg')]
    bg_url_pattern = ~r/bg-\[url\(['"]([^'"]+)['"]\)\]/i
    Regex.replace(bg_url_pattern, content, fn full_match, image_path ->
      if is_relative_link?(image_path) do
        "bg-[url('/preview/#{watcher_id}/asset?file=#{image_path}')]"
      else
        full_match
      end
    end, global: true)
  end

  defp rewrite_gradient_patterns(content, watcher_id) do
    # Handle gradient patterns that might reference images
    # Example: bg-gradient-to-r from-[url('image.jpg')] to-[url('image2.jpg')]
    gradient_url_pattern = ~r/(from|to|via)-\[url\(['"]([^'"]+)['"]\)\]/i
    Regex.replace(gradient_url_pattern, content, fn full_match, direction, image_path ->
      if is_relative_link?(image_path) do
        "#{direction}-[url('/preview/#{watcher_id}/asset?file=#{image_path}')]"
      else
        full_match
      end
    end, global: true)
  end

  defp rewrite_mask_patterns(content, watcher_id) do
    # Handle mask patterns like mask-[url('mask.svg')]
    mask_url_pattern = ~r/mask-\[url\(['"]([^'"]+)['"]\)\]/i
    Regex.replace(mask_url_pattern, content, fn full_match, mask_path ->
      if is_relative_link?(mask_path) do
        "mask-[url('/preview/#{watcher_id}/asset?file=#{mask_path}')]"
      else
        full_match
      end
    end, global: true)
  end

  defp rewrite_clip_path_patterns(content, watcher_id) do
    # Handle clip-path patterns like clip-path-[url('path.svg')]
    clip_path_pattern = ~r/clip-path-\[url\(['"]([^'"]+)['"]\)\]/i
    Regex.replace(clip_path_pattern, content, fn full_match, clip_path ->
      if is_relative_link?(clip_path) do
        "clip-path-[url('/preview/#{watcher_id}/asset?file=#{clip_path}')]"
      else
        full_match
      end
    end, global: true)
  end

  defp is_relative_link?(path) do
    # Check if the path is relative (doesn't start with http://, https://, //, or #)
    # Note: We DO want to rewrite paths starting with / to be preview links
    not (String.starts_with?(path, "http://") or
         String.starts_with?(path, "https://") or
         String.starts_with?(path, "//") or
         String.starts_with?(path, "#"))
  end

  defp is_html_link?(path) do
    ext = Path.extname(path)
    ext == ".html" or ext == ""
  end

  defp convert_path_to_file(path) do
    cond do
      # If it's already a .html file, return as is
      String.ends_with?(path, ".html") ->
        path
      # If it's empty (root path), return index.html
      path == "/" ->
        "index.html"
      # Otherwise, assume it's a directory and append index.html
      true ->
        "#{path}index.html"
    end
  end

  defp serve_asset(conn, file_path) do
    content = File.read!(file_path)
    content_type = get_content_type(file_path)

    conn
    |> put_resp_content_type(content_type)
    |> send_resp(200, content)
  end

  defp get_content_type(file_path) do
    case String.downcase(Path.extname(file_path)) do
      ".css" -> "text/css"
      ".js" -> "application/javascript"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".svg" -> "image/svg+xml"
      ".webp" -> "image/webp"
      ".woff" -> "font/woff"
      ".woff2" -> "font/woff2"
      ".ttf" -> "font/ttf"
      ".eot" -> "application/vnd.ms-fontobject"
      _ -> "application/octet-stream"
    end
  end

  defp build_file_structure(root_path, path_to_config) do
    if File.dir?(root_path) do
      try do
        File.ls!(root_path)
        |> Enum.sort_by(fn item ->
          item_path = Path.join(root_path, item)
          {!File.dir?(item_path), String.downcase(item)}
        end)
        |> Enum.with_index()
        |> Enum.flat_map(fn {item, index} ->
          item_path = Path.join(root_path, item)
          items = File.ls!(root_path)
          is_last = index == length(items) - 1

          if File.dir?(item_path) do
            # Add the folder itself
            folder_item = %{
              name: item,
              path: item_path,
              is_dir: true,
              is_file: false,
              is_html: false,
              relative_path: Path.relative_to(item_path, root_path),
              depth: 0,
              is_last: is_last
            }

            # Recursively add contents of the folder
            contents = build_file_structure(item_path, path_to_config)
            |> Enum.map(fn content ->
              Map.put(content, :depth, content.depth + 1)
            end)

            [folder_item | contents]
          else
            # Add the file
            [%{
              name: item,
              path: item_path,
              is_dir: false,
              is_file: true,
              is_html: String.ends_with?(item, ".html"),
              relative_path: Path.relative_to(item_path, path_to_config),
              depth: 0,
              is_last: is_last
            }]
          end
        end)
      rescue
        _ -> []
      end
    else
      []
    end
  end
end
