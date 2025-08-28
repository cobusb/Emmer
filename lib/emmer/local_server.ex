defmodule Emmer.LocalServer do
  @moduledoc """
  Handles distributed Erlang requests from the cloud proxy.
  This module runs on the local Emmer server and responds to file/asset requests.
  """

  require Logger

  @doc """
  Handle file request from cloud proxy
  """
  def get_file(server_id, file_path) do
    Logger.info("LocalServer: Received file request for #{file_path} from server #{server_id}")

    # Get the current process ID for response tracking
    caller = self()

    # Spawn a process to handle the request asynchronously
    spawn(fn ->
      result = handle_file_request(server_id, file_path)
      send(caller, {:file_response, self(), result})
    end)
  end

  @doc """
  Handle asset request from cloud proxy
  """
  def get_asset(server_id, asset_path) do
    Logger.info("LocalServer: Received asset request for #{asset_path} from server #{server_id}")

    # Get the current process ID for response tracking
    caller = self()

    # Spawn a process to handle the request asynchronously
    spawn(fn ->
      result = handle_asset_request(server_id, asset_path)
      send(caller, {:asset_response, self(), result})
    end)
  end

  # Private functions

  defp handle_file_request(server_id, file_path) do
    try do
      # Get the Emmer from the database
      case Emmer.Repo.get(Emmer.EmmerRoot, server_id) do
        nil ->
          {:error, "Emmer not found"}

        emmer ->
          # Build the output file path
          output_file = Path.join(emmer.output_dir, file_path)

          # Check if file exists
          if File.exists?(output_file) do
            # Read the file content
            content = File.read!(output_file)

            # Rewrite links for preview (same logic as PreviewController)
            rewritten_content = rewrite_links_for_preview(content, server_id)

            {:ok, rewritten_content}
          else
            {:error, "File not found: #{file_path}"}
          end
      end
    rescue
      e ->
        Logger.error("Error handling file request: #{inspect(e)}")
        {:error, "Internal server error"}
    end
  end

  defp handle_asset_request(server_id, asset_path) do
    try do
      # Get the Emmer from the database
      case Emmer.Repo.get(Emmer.EmmerRoot, server_id) do
        nil ->
          {:error, "Emmer not found"}

        emmer ->
          # Build the asset file path
          asset_file = Path.join(emmer.output_dir, asset_path)

          # Check if file exists
          if File.exists?(asset_file) do
            # Read the file content
            content = File.read!(asset_file)

            # Determine content type
            content_type = get_content_type(asset_path)

            # Set appropriate headers
            headers = [
              {"content-type", content_type},
              {"content-length", "#{byte_size(content)}"}
            ]

            {:ok, content, headers}
          else
            {:error, "Asset not found: #{asset_path}"}
          end
      end
    rescue
      e ->
        Logger.error("Error handling asset request: #{inspect(e)}")
        {:error, "Internal server error"}
    end
  end

  defp rewrite_links_for_preview(content, emmer_id) do
    # Rewrite relative links to point to cloud preview
    content
    |> rewrite_file_links(emmer_id)
    |> rewrite_asset_links(emmer_id)
  end

  defp rewrite_file_links(content, emmer_id) do
    # Rewrite links like href="/about/" to preview URLs
    link_pattern = ~r/href=["']([^"']*)[\"']/i
    Regex.replace(link_pattern, content, fn _full, link_path ->
      if is_relative_link?(link_path) and is_html_link?(link_path) do
        file_path = convert_path_to_file(link_path)
        "href=\"/preview/#{emmer_id}/file?file=#{file_path}\""
      else
        "href=\"#{link_path}\""
      end
    end, global: true)
  end

  defp rewrite_asset_links(content, emmer_id) do
    # Rewrite asset links to point to preview asset proxy
    asset_pattern = ~r/(src|href)=["']([^"']*\.(css|js|png|jpg|jpeg|gif|svg|woff|woff2|ttf|eot))["']/i
    Regex.replace(asset_pattern, content, fn _full, attr, asset_path ->
      if is_relative_link?(asset_path) do
        "#{attr}=\"/preview/#{emmer_id}/asset?file=#{asset_path}\""
      else
        "#{attr}=\"#{asset_path}\""
      end
    end, global: true)
  end

  defp is_relative_link?(path) do
    # Check if the path is relative (doesn't start with http://, https://, //, or #)
    not (String.starts_with?(path, "http://") or
         String.starts_with?(path, "https://") or
         String.starts_with?(path, "//") or
         String.starts_with?(path, "#"))
  end

  defp is_html_link?(path) do
    # Check if this is an HTML page link (not an asset)
    not (String.ends_with?(path, ".css") or
         String.ends_with?(path, ".js") or
         String.ends_with?(path, ".png") or
         String.ends_with?(path, ".jpg") or
         String.ends_with?(path, ".jpeg") or
         String.ends_with?(path, ".gif") or
         String.ends_with?(path, ".svg") or
         String.ends_with?(path, ".woff") or
         String.ends_with?(path, ".woff2") or
         String.ends_with?(path, ".ttf") or
         String.ends_with?(path, ".eot"))
  end

  defp convert_path_to_file(path) do
    # Remove leading slash and trailing slash
    clean_path = path
    |> String.trim_leading("/")
    |> String.trim_trailing("/")

    # Convert directory paths to index.html
    if clean_path == "" do
      "index.html"
    else
      # Check if it ends with .html, if not add /index.html
      if String.ends_with?(clean_path, ".html") do
        clean_path
      else
        "#{clean_path}/index.html"
      end
    end
  end

  defp get_content_type(file_path) do
    case Path.extname(file_path) do
      ".css" -> "text/css"
      ".js" -> "application/javascript"
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".svg" -> "image/svg+xml"
      ".woff" -> "font/woff"
      ".woff2" -> "font/woff2"
      ".ttf" -> "font/ttf"
      ".eot" -> "application/vnd.ms-fontobject"
      _ -> "application/octet-stream"
    end
  end
end
