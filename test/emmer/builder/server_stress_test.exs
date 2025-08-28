defmodule Emmer.Builder.ServerStressTest do
  use ExUnit.Case, async: false
  
  import Emmer.TestHelpers
  
  alias Emmer.Builder.Server
  
  @moduletag :stress
  @moduletag timeout: 120_000  # 2 minutes for stress tests
  
  setup do
    {:ok, _} = start_test_supervisors()
    
    on_exit(fn ->
      cleanup_test_environment()
    end)
    
    :ok
  end
  
  describe "stress tests" do
    test "handles rapid start/stop cycles" do
      test_folder = "/tmp/emmer_stress_test_#{System.unique_integer([:positive])}"
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      # Rapid start/stop cycles
      for i <- 1..10 do
        Server.full_build(test_folder)
        assert_receive {:build_started, build_id, ^test_folder}, 5_000
        
        # Random delay before stopping
        :timer.sleep(:rand.uniform(500))
        
        Server.stop_build(test_folder)
        assert_receive {:build_stopped, ^build_id}, 5_000
        
        # Verify server is still alive
        assert Process.alive?(pid)
      end
    end
    
    test "handles many concurrent progress updates" do
      test_folder = "/tmp/emmer_stress_concurrent_#{System.unique_integer([:positive])}"
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      {:ok, pid} = Server.start_link(test_folder)
      Server.full_build(test_folder)
      
      receive do
        {:build_started, build_id, ^test_folder} ->
          # Spawn many processes sending progress updates
          tasks = for i <- 1..100 do
            Task.async(fn ->
              for j <- 1..10 do
                send(pid, {:build_progress, build_id, %{
                  type: Enum.random([:folder_started, :agent_created, :record_processed]),
                  folder: "folder_#{i}_#{j}",
                  agent: "agent_#{i}_#{j}",
                  count: 1
                }})
                :timer.sleep(10)
              end
            end)
          end
          
          # Wait for all tasks
          Enum.each(tasks, &Task.await(&1, 10_000))
          
          # Server should still be responsive
          assert {:ok, progress} = Server.get_build_progress(test_folder)
          assert progress.folders_count > 0
          assert Process.alive?(pid)
      after
        10_000 -> flunk("Build did not start")
      end
    end
    
    test "handles very large folder structures" do
      test_folder = "/tmp/emmer_stress_large_#{System.unique_integer([:positive])}"
      
      # Create deeply nested folder structure
      base_content = Path.join(test_folder, "content")
      create_deep_folder_structure(base_content, 5, 3)
      create_test_yaml_config(test_folder)
      
      {:ok, _pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      # Memory before build
      {:memory, memory_before} = Process.info(self(), :memory)
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5_000
      
      # Monitor memory usage during build
      monitor_task = Task.async(fn ->
        monitor_memory_usage(test_folder, build_id, 30_000)
      end)
      
      # Wait for completion or timeout
      case wait_for_build_completion(test_folder, 60_000) do
        {:ok, ^build_id, _state} ->
          {:ok, progress} = Server.get_build_progress(test_folder)
          assert progress.status == :completed
          
          # Check memory didn't grow excessively
          {:memory, memory_after} = Process.info(self(), :memory)
          memory_growth = memory_after - memory_before
          
          # Memory growth should be reasonable (adjust threshold as needed)
          assert memory_growth < 100_000_000, "Excessive memory growth: #{memory_growth} bytes"
          
        {:error, :timeout} ->
          flunk("Build timed out for large folder structure")
      end
      
      Task.shutdown(monitor_task, :brutal_kill)
    end
    
    test "handles file system errors gracefully" do
      test_folder = "/tmp/emmer_stress_fs_errors_#{System.unique_integer([:positive])}"
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      {:ok, pid} = Server.start_link(test_folder)
      Server.full_build(test_folder)
      
      receive do
        {:build_started, build_id, ^test_folder} ->
          # Simulate file system issues by removing directories during build
          Task.start(fn ->
            :timer.sleep(500)
            # Remove a content directory (non-destructive test)
            test_dir = Path.join(test_folder, "content/test_remove")
            File.mkdir_p!(test_dir)
            File.write!(Path.join(test_dir, "test.md"), "test content")
            :timer.sleep(100)
            File.rm_rf!(test_dir)
          end)
          
          # Server should handle this gracefully
          :timer.sleep(2_000)
          assert Process.alive?(pid)
          
          # Should still be able to get progress
          assert {:ok, _progress} = Server.get_build_progress(test_folder)
      after
        10_000 -> flunk("Build did not start")
      end
    end
  end
  
  describe "resource cleanup" do
    test "properly cleans up resources after multiple builds" do
      test_folder = "/tmp/emmer_stress_cleanup_#{System.unique_integer([:positive])}"
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      {:ok, pid} = Server.start_link(test_folder)
      
      # Run multiple complete build cycles
      for i <- 1..5 do
        Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
        
        Server.full_build(test_folder)
        assert_receive {:build_started, build_id, ^test_folder}, 5_000
        
        # Wait for completion
        case wait_for_build_completion(test_folder, 20_000) do
          {:ok, ^build_id, _state} ->
            # Clean up old processes
            Server.cleanup_old_processes(test_folder)
            :timer.sleep(500)
            
          {:error, :timeout} ->
            # Stop the build if it's taking too long
            Server.stop_build(test_folder)
            assert_receive {:build_stopped, ^build_id}, 5_000
        end
        
        Phoenix.PubSub.unsubscribe(Emmer.PubSub, "builder:#{test_folder}")
      end
      
      # Server should still be healthy
      assert Process.alive?(pid)
      
      # Should have reasonable memory usage
      {:memory, memory} = Process.info(pid, :memory)
      assert memory < 50_000_000, "Server using too much memory: #{memory} bytes"
    end
  end
  
  # Helper functions
  
  defp create_deep_folder_structure(base_path, depth, width) when depth <= 0 do
    # Create a file at the leaf
    File.mkdir_p!(base_path)
    File.write!(Path.join(base_path, "content.md"), """
    ---
    title: Deep content
    ---
    Content at #{base_path}
    """)
  end
  
  defp create_deep_folder_structure(base_path, depth, width) do
    File.mkdir_p!(base_path)
    
    for i <- 1..width do
      sub_path = Path.join(base_path, "folder_#{i}")
      create_deep_folder_structure(sub_path, depth - 1, width)
    end
  end
  
  defp monitor_memory_usage(folder_path, build_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    monitor_memory_loop(folder_path, build_id, deadline, [])
  end
  
  defp monitor_memory_loop(_folder_path, _build_id, deadline, measurements) do
    now = System.monotonic_time(:millisecond)
    
    if now >= deadline do
      # Return memory statistics
      %{
        measurements: measurements,
        peak: Enum.max_by(measurements, fn {_time, mem} -> mem end),
        average: calculate_average_memory(measurements)
      }
    else
      # Get current memory usage
      {:memory, current_memory} = Process.info(self(), :memory)
      
      # Add measurement
      new_measurements = [{now, current_memory} | measurements]
      
      # Continue monitoring
      :timer.sleep(100)
      monitor_memory_loop(_folder_path, _build_id, deadline, new_measurements)
    end
  end
  
  defp calculate_average_memory(measurements) do
    total = Enum.reduce(measurements, 0, fn {_time, mem}, acc -> acc + mem end)
    count = length(measurements)
    if count > 0, do: div(total, count), else: 0
  end
end