defmodule Emmer.RunTest do

alias Emmer.Builder.ServerSupervisor

def run_test do
  case ServerSupervisor.find_or_create("../vgkjhb-emmer") do
    {:ok, _pid} ->
      Emmer.Builder.Server.full_build("../vgkjhb-emmer")
    {:exists, folder_path} ->
      Emmer.Builder.Server.full_build("../vgkjhb-emmer")
    {:error, reason} ->
      Logger.error("Failed to create build server: #{inspect(reason)}")
  end
end
end
