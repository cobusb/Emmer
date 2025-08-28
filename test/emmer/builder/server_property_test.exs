defmodule Emmer.Builder.ServerPropertyTest do
  use ExUnit.Case, async: false
  
  alias Emmer.Builder.Server
  import Emmer.TestHelpers
  
  @moduletag :property
  
  setup do
    {:ok, _} = start_test_supervisors()
    
    on_exit(fn ->
      cleanup_test_environment()
    end)
    
    :ok
  end
  
  describe "build_id generation properties" do
    test "build_ids are unique" do
      folder = "/tmp/test_folder"
      
      # Generate multiple build IDs
      build_ids = for _ <- 1..100 do
        # Use module function directly for testing
        generate_test_build_id(folder)
      end
      
      # All should be unique
      assert length(build_ids) == length(Enum.uniq(build_ids))
    end
    
    test "build_ids follow expected format" do
      folder = "/tmp/test_folder"
      
      for _ <- 1..50 do
        build_id = generate_test_build_id(folder)
        assert build_id =~ ~r/^build_\d{10,}_[a-f0-9]{8}$/
      end
    end
  end
  
  describe "state transition properties" do
    test "state transitions are valid" do
      test_folder = "/tmp/emmer_property_#{System.unique_integer([:positive])}"
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      {:ok, pid} = Server.start_link(test_folder)
      
      # Initial state should have nil status
      {:ok, state} = :sys.get_state(pid)
      assert state.status == nil
      
      # After starting build, status should be building or failed
      Server.full_build(test_folder)
      :timer.sleep(500)
      
      {:ok, state} = :sys.get_state(pid)
      assert state.status in [:building, :failed]
      
      # After stopping, status should be stopped
      if state.status == :building do
        Server.stop_build(test_folder)
        :timer.sleep(500)
        
        {:ok, state} = :sys.get_state(pid)
        assert state.status == :stopped
      end
    end
    
    test "progress values are monotonic" do
      test_folder = "/tmp/emmer_monotonic_#{System.unique_integer([:positive])}"
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      
      receive do
        {:build_started, build_id, ^test_folder} ->
          # Collect progress over time
          progress_values = for _ <- 1..10 do
            # Simulate progress
            send(pid, {:build_progress, build_id, %{type: :record_processed, count: 1}})
            :timer.sleep(50)
            
            case Server.get_build_progress(test_folder) do
              {:ok, progress} -> progress.processed_records
              _ -> 0
            end
          end
          
          # Progress should never decrease
          assert progress_values == Enum.sort(progress_values)
      after
        5_000 -> flunk("Build did not start")
      end
    end
  end
  
  describe "concurrent operation properties" do
    test "concurrent progress updates maintain consistency" do
      test_folder = "/tmp/emmer_concurrent_#{System.unique_integer([:positive])}"
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      {:ok, pid} = Server.start_link(test_folder)
      Server.full_build(test_folder)
      
      receive do
        {:build_started, build_id, ^test_folder} ->
          # Send many concurrent updates
          total_records = 1000
          
          tasks = for _ <- 1..10 do
            Task.async(fn ->
              for _ <- 1..100 do
                send(pid, {:build_progress, build_id, %{type: :record_processed, count: 1}})
              end
            end)
          end
          
          # Wait for all tasks
          Enum.each(tasks, &Task.await/1)
          :timer.sleep(500)
          
          # Total should match
          {:ok, progress} = Server.get_build_progress(test_folder)
          assert progress.processed_records == total_records
      after
        5_000 -> flunk("Build did not start")
      end
    end
  end
  
  describe "error handling properties" do
    test "errors don't corrupt state" do
      test_folder = "/tmp/emmer_errors_#{System.unique_integer([:positive])}"
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      {:ok, pid} = Server.start_link(test_folder)
      Server.full_build(test_folder)
      
      receive do
        {:build_started, build_id, ^test_folder} ->
          # Send various valid and invalid messages
          messages = [
            {:build_progress, build_id, %{type: :folder_started, folder: "valid"}},
            {:build_progress, "wrong_id", %{type: :folder_started, folder: "ignored"}},
            {:build_progress, build_id, %{type: :unknown_type, data: "ignored"}},
            {:build_progress, build_id, nil},
            {:build_progress, build_id, %{type: :agent_created, agent: "valid_agent"}},
            {:unknown_message, build_id, %{data: "ignored"}},
            {:build_progress, build_id, %{type: :record_processed, count: 5}}
          ]
          
          Enum.each(messages, fn msg -> send(pid, msg) end)
          :timer.sleep(500)
          
          # State should still be valid
          assert Process.alive?(pid)
          {:ok, progress} = Server.get_build_progress(test_folder)
          
          # Only valid updates should be reflected
          assert progress.folders_count == 1
          assert progress.agents_count == 1
          assert progress.processed_records == 5
      after
        5_000 -> flunk("Build did not start")
      end
    end
  end
  
  describe "invariant properties" do
    test "progress percentage is always between 0 and 100" do
      test_folder = "/tmp/emmer_percentage_#{System.unique_integer([:positive])}"
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      {:ok, pid} = Server.start_link(test_folder)
      Server.full_build(test_folder)
      
      receive do
        {:build_started, build_id, ^test_folder} ->
          # Test various record counts
          test_cases = [
            {0, 0},      # No records
            {50, 100},   # Half complete
            {100, 100},  # Fully complete
            {150, 100},  # More processed than total (edge case)
            {0, 1000},   # No progress on large total
          ]
          
          for {processed, total} <- test_cases do
            send(pid, {:build_progress, build_id, %{type: :total_records, count: total}})
            send(pid, {:build_progress, build_id, %{type: :record_processed, count: processed}})
            :timer.sleep(50)
            
            {:ok, progress} = Server.get_build_progress(test_folder)
            
            # Percentage should always be valid
            assert progress.progress_percentage >= 0
            assert progress.progress_percentage <= 100
          end
      after
        5_000 -> flunk("Build did not start")
      end
    end
    
    test "active folder count never goes negative" do
      test_folder = "/tmp/emmer_folder_count_#{System.unique_integer([:positive])}"
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      {:ok, pid} = Server.start_link(test_folder)
      Server.full_build(test_folder)
      
      receive do
        {:build_started, build_id, ^test_folder} ->
          # Try to make folder count go negative
          for _ <- 1..5 do
            send(pid, {:build_progress, build_id, %{type: :folder_completed, folder: "folder_#{:rand.uniform(100)}"}})
          end
          
          :timer.sleep(200)
          
          {:ok, state} = :sys.get_state(pid)
          assert state.active_folder_count >= 0
          
          # Now add some folders and complete them
          send(pid, {:build_progress, build_id, %{type: :folder_started, folder: "real_folder"}})
          send(pid, {:build_progress, build_id, %{type: :folder_completed, folder: "real_folder"}})
          
          :timer.sleep(200)
          
          {:ok, state} = :sys.get_state(pid)
          assert state.active_folder_count >= 0
      after
        5_000 -> flunk("Build did not start")
      end
    end
  end
  
  # Helper function to generate build IDs for testing
  defp generate_test_build_id(folder_path) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    hash = :crypto.hash(:sha256, folder_path) |> Base.encode16(case: :lower)
    "build_#{timestamp}_#{String.slice(hash, 0, 8)}"
  end
end