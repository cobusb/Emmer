defmodule Emmer.BuildLoggerBackend do
  @behaviour :gen_event

  defstruct [
    :level,
    :metadata_filter,
    :registry_name,
    :format,
    :colors
  ]

  def init(__MODULE__) do
    init({__MODULE__, []})
  end

  def init({__MODULE__, opts}) do
    config = configure(opts)
    {:ok, config}
  end

  def handle_call({:configure, opts}, state) do
    {:ok, :ok, configure(opts, state)}
  end

  def handle_event({level, _gl, {Logger, msg, ts, metadata}}, state) do
    if meet_level?(level, state.level) and should_dispatch?(metadata, state) do
      dispatch_to_builds(level, msg, ts, metadata, state)
    end
    {:ok, state}
  end

  def handle_event(:flush, state) do
    {:ok, state}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  def code_change(_old, state, _extra) do
    {:ok, state}
  end

  defp meet_level?(_level, nil), do: true
  defp meet_level?(level, min) do
    Logger.compare_levels(level, min) != :lt
  end

  defp should_dispatch?(metadata, state) do
    # Only dispatch if metadata indicates it's from a build process
    case metadata[:build_folder] do
      nil -> false
      _folder -> passes_metadata_filter?(metadata, state.metadata_filter)
    end
  end

  defp passes_metadata_filter?(_metadata, nil), do: true
  defp passes_metadata_filter?(metadata, filters) when is_list(filters) do
    Enum.all?(filters, fn {key, val} ->
      Keyword.get(metadata, key) == val
    end)
  end

  defp dispatch_to_builds(level, msg, ts, metadata, state) do
    build_folder = metadata[:build_folder]
    
    # Get all GenServers watching this build folder
    case Registry.lookup(state.registry_name, {:build_listener, build_folder}) do
      [] -> 
        :ok
      
      watchers ->
        formatted_msg = format_message(level, msg, ts, metadata, state)
        
        Enum.each(watchers, fn {pid, _value} ->
          send(pid, {:build_log, build_folder, level, formatted_msg, metadata})
        end)
    end
  end

  defp format_message(level, msg, ts, metadata, state) do
    if state.format do
      state.format
      |> Logger.Formatter.compile()
      |> Logger.Formatter.format(level, msg, ts, metadata)
      |> IO.iodata_to_binary()
    else
      msg
    end
  end

  defp configure(opts, state \\ %__MODULE__{}) do
    config = Application.get_env(:logger, __MODULE__, [])
    config = Keyword.merge(config, opts)
    
    %__MODULE__{
      level: Keyword.get(config, :level),
      metadata_filter: Keyword.get(config, :metadata_filter),
      registry_name: Keyword.get(config, :registry_name, Emmer.Builder.BuildRegistry),
      format: Keyword.get(config, :format, "$time $metadata[$level] $message\n"),
      colors: Keyword.get(config, :colors, [])
    }
  end
end