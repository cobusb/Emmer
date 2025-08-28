defmodule Emmer.Processor.Wait do
  @moduledoc """
  A processor that waits for a configurable number of seconds.

  This processor can be used for testing, debugging, or simulating slow operations.
  It works both as a regular processor (waits for each record) and as a post-processor
  (waits once after all files are processed).

  ## Configuration

  * `seconds` - Number of seconds to wait (required)
  * `message` - Optional custom message to log (defaults to "Waiting...")

  ## Examples

  ### As a regular processor (waits for each record)
  ```yaml
  processors:
    - name: "wait_per_file"
      module: "Emmer.Processor.Wait"
      seconds: 2
      message: "Processing file - waiting 2 seconds"
      filter:
        regex: "\\.html$"
  ```

  ### As a post-processor (waits once at the end)
  ```yaml
  processors:
    - name: "final_wait"
      module: "Emmer.Processor.Wait"
      post_processor: true
      seconds: 5
      message: "Build complete - cooling down for 5 seconds"
  ```
  """

  use Task
  alias Emmer.Builder.BuildLogger

  def start_link(record, processor, context) do
    Task.start_link(__MODULE__, :build, [record, processor, context])
  end

  def build(record, processor, context) do
    build_id = context[:build_id] || "unknown"
    root_folder_path = context[:root_folder_path] || context["root_folder_path"] || "."

    # Get configuration
    seconds = processor["seconds"]
    message = processor["message"] || "Waiting..."

    # Validate configuration
    case validate_seconds(seconds) do
      {:error, reason} ->
        BuildLogger.error(root_folder_path, "#{build_id} Wait processor configuration error: #{reason}")
        {:error, reason}

      {:ok, wait_seconds} ->
        # Determine if this is a post-processor or regular processor
        is_post_processor = processor["post_processor"] == true

        if is_post_processor do
          # Post-processor: log once and wait
          BuildLogger.info(root_folder_path, "#{build_id} Wait (post-processor): #{message} - waiting #{wait_seconds} seconds")
          perform_wait(wait_seconds, build_id, root_folder_path)
        else
          # Regular processor: log per record and wait
          record_info = get_record_info(record)
          BuildLogger.info(root_folder_path, "#{build_id} Wait (#{record_info}): #{message} - waiting #{wait_seconds} seconds")
          perform_wait(wait_seconds, build_id, root_folder_path)
        end

        BuildLogger.debug(root_folder_path, "#{build_id} Wait processor completed")
        {:ok}
    end
  end

  defp validate_seconds(seconds) when is_number(seconds) and seconds > 0 do
    {:ok, seconds}
  end

  defp validate_seconds(seconds) when is_binary(seconds) do
    case Float.parse(seconds) do
      {parsed_seconds, ""} when parsed_seconds > 0 ->
        {:ok, parsed_seconds}
      _ ->
        {:error, "Invalid seconds value: '#{seconds}'. Must be a positive number."}
    end
  end

  defp validate_seconds(nil) do
    {:error, "Missing required 'seconds' configuration"}
  end

  defp validate_seconds(seconds) do
    {:error, "Invalid seconds value: #{inspect(seconds)}. Must be a positive number."}
  end

  defp perform_wait(seconds, build_id, root_folder_path) do
    # Convert to milliseconds for Process.sleep
    milliseconds = trunc(seconds * 1000)

    BuildLogger.debug(root_folder_path, "#{build_id} Wait: Sleeping for #{milliseconds}ms")
    Process.sleep(milliseconds)
    BuildLogger.debug(root_folder_path, "#{build_id} Wait: Sleep completed")
  end

  defp get_record_info(record) when is_map(record) do
    case record["path"] do
      nil -> "unknown record"
      path -> Path.basename(path)
    end
  end

  defp get_record_info(record) when is_binary(record) do
    Path.basename(record)
  end

  defp get_record_info(_record) do
    "unknown record"
  end
end
