defmodule Emmer.Processor.EctoLiquidStaticSite do
  @moduledoc """
  Processor for EctoLiquidStaticSite
  """
  def start_link(record, processor, context) do
    Task.start_link(__MODULE__, :build, [record, processor, context])
  end
  
  def build(record, processor, context) do
    build_id = context[:build_id] || "unknown"
    root_folder_path = context[:root_folder_path] || context["root_folder_path"] || "."

    
    
  end
end