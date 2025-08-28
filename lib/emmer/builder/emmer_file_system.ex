defmodule Emmer.Builder.EmmerFileSystem do
  @moduledoc """
  A custom Solid FileSystem implementation that supports multiple file extensions.

  This filesystem tries multiple extensions in order when looking for template files:
  - .html
  - .md
  - .liquid
  - no extension (exact match)

  Usage:
    filesystem = Emmer.Builder.EmmerFileSystem.new("/path/to/templates", "%s")
    Solid.render(template, context, file_system: {Emmer.Builder.EmmerFileSystem, filesystem})
  """

  @behaviour Solid.FileSystem

  defstruct [:root, :pattern]

  @doc """
  Creates a new EmmerFileSystem instance.

  ## Parameters
  - root: The root directory where templates are located
  - pattern: The pattern for template names (default: "%s")
  """
  def new(root, pattern \\ "%s") do
    %__MODULE__{
      root: root,
      pattern: pattern
    }
  end

  @impl true
  def read_template_file(template_path, file_system) do
    # List of extensions to try, in order
    extensions = [".html", ".md", ".liquid"]

    IO.inspect(extensions, label: "extensions!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")

    # Try each extension until we find a file
    result = Enum.find_value(extensions, fn ext ->
      case try_read_with_extension(template_path, file_system, ext) do
        {:ok, content} -> {:ok, content}
        {:error, _} -> nil
      end
    end)

    case result do
      {:ok, content} ->
        {:ok, content}
      nil ->
        {:error, %Solid.FileSystem.Error{reason: "No such template '#{template_path}' (tried extensions: #{inspect(extensions)})"}}
    end
  end

  defp try_read_with_extension(template_path, file_system, extension) do
    with {:ok, full_path} <- build_full_path(template_path, file_system, extension) do
      if File.exists?(full_path) do
        IO.inspect(full_path, label: "full_path!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        {:ok, File.read!(full_path)}
      else
        {:error, :not_found}
      end
    end
  end

  defp build_full_path(template_path, file_system, extension) do
    # Security check: only allow safe template paths
    if String.match?(template_path, Regex.compile!("^[^./][a-zA-Z0-9_/-]+$")) do
      # Build the template name with extension
      template_name = String.replace(file_system.pattern, "%s", Path.basename(template_path)) <> extension

      # Build the full path
      full_path =
        if String.contains?(template_path, "/") do
          file_system.root
          |> Path.join(Path.dirname(template_path))
          |> Path.join(template_name)
          |> Path.expand()
        else
          file_system.root
          |> Path.join(template_name)
          |> Path.expand()
        end

      # Security check: ensure path is within root directory
      if String.starts_with?(full_path, Path.expand(file_system.root)) do
        {:ok, full_path}
      else
        {:error, %Solid.FileSystem.Error{reason: "Illegal template path '#{Path.expand(full_path)}'"}}
      end
    else
      {:error, %Solid.FileSystem.Error{reason: "Illegal template name '#{template_path}'"}}
    end
  end
end
