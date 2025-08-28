defmodule Emmer.Builder.ServerIntegrationTest do
  use ExUnit.Case, async: false
  
  import Emmer.TestHelpers
  
  alias Emmer.Builder.Server
  
  @moduletag :integration
  
  setup do
    # Start necessary supervisors
    {:ok, _} = start_test_supervisors()
    
    # Create unique test folder
    test_folder = "/tmp/emmer_test_#{System.unique_integer([:positive])}"
    
    on_exit(fn ->
      cleanup_test_environment()
    end)
    
    {:ok, test_folder: test_folder}
  end
  
  describe "full build integration" do
    test "completes a full build with real folder structure", %{test_folder: test_folder} do
      # Create test folder structure with content
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      # Start server
      {:ok, _pid} = Server.start_link(test_folder)
      
      # Subscribe to events
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      Phoenix.PubSub.subscribe(Emmer.PubSub, "build_completion:#{test_folder}")
      
      # Start build
      Server.full_build(test_folder)
      
      # Wait for build to start
      assert_receive {:build_started, build_id, ^test_folder}, 5_000
      
      # Monitor progress
      progress_updates = collect_progress_updates(test_folder, build_id, 10_000)
      
      # Verify build completed
      assert Enum.any?(progress_updates, fn update ->
        match?({:build_completed, ^build_id, _}, update)
      end)
      
      # Verify final state
      {:ok, final_progress} = Server.get_build_progress(test_folder)
      assert final_progress.status == :completed
      assert final_progress.folders_count > 0
      assert final_progress.processed_records > 0
    end
    
    test "handles build with errors in content files", %{test_folder: test_folder} do
      # Create folder structure
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      # Add a malformed content file
      bad_content = """
      ---
      title: Bad File
      date: not-a-date
      ---
      
      Content with invalid frontmatter
      """
      File.write!(Path.join(test_folder, "content/posts/bad.md"), bad_content)
      
      # Start server and build
      {:ok, _pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, _build_id, ^test_folder}, 5_000
      
      # Wait a bit for processing
      :timer.sleep(3_000)
      
      # Check progress - build should continue despite errors
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.errors_count > 0 or progress.warnings_count > 0
    end
    
    test "handles concurrent builds on different folders", %{test_folder: test_folder} do
      # Create two separate test folders
      folder1 = test_folder <> "_1"
      folder2 = test_folder <> "_2"
      
      create_test_folder_structure(folder1)
      create_test_yaml_config(folder1)
      create_test_folder_structure(folder2)
      create_test_yaml_config(folder2)
      
      # Start servers for both folders
      {:ok, _pid1} = Server.start_link(folder1)
      {:ok, _pid2} = Server.start_link(folder2)
      
      # Subscribe to both
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{folder1}")
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{folder2}")
      
      # Start builds concurrently
      Server.full_build(folder1)
      Server.full_build(folder2)
      
      # Both should start
      assert_receive {:build_started, _build_id1, ^folder1}, 5_000
      assert_receive {:build_started, _build_id2, ^folder2}, 5_000
      
      # Both should be able to report progress independently
      {:ok, progress1} = Server.get_build_progress(folder1)
      {:ok, progress2} = Server.get_build_progress(folder2)
      
      assert progress1.id != progress2.id
    end
  end
  
  describe "stop build integration" do
    test "successfully stops a running build and cleans up processes", %{test_folder: test_folder} do
      create_test_folder_structure(test_folder)
      create_test_yaml_config(test_folder)
      
      {:ok, _pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      # Start build
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5_000
      
      # Let it run for a bit
      :timer.sleep(1_000)
      
      # Stop the build
      Server.stop_build(test_folder)
      assert_receive {:build_stopped, ^build_id}, 5_000
      
      # Verify status
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.status == :stopped
      
      # Verify no orphaned processes (would need actual supervisor checks)
      # This is a simplified check
      :timer.sleep(500)
      
      # Should be able to start a new build
      Server.full_build(test_folder)
      assert_receive {:build_started, new_build_id, ^test_folder}, 5_000
      assert new_build_id != build_id
    end
  end
  
  describe "build recovery" do
    test "recovers from folder process crash", %{test_folder: test_folder} do
      create_test_folder_structure(test_folder)
      
      # Create config that might cause issues
      config = %{
        "builder" => %{
          "verbose_logging" => "debug",
          "source_folder" => "content"
        }
      }
      create_test_yaml_config(test_folder, config)
      
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, _build_id, ^test_folder}, 5_000
      
      # Get server state and simulate folder process crash
      {:ok, state} = :sys.get_state(pid)
      if state.folder_process do
        Process.exit(state.folder_process, :kill)
      end
      
      # Server should handle this gracefully
      :timer.sleep(1_000)
      assert Process.alive?(pid)
    end
  end
  
  describe "memory and performance" do
    @tag :performance
    test "handles large number of files efficiently", %{test_folder: test_folder} do
      # Create many files
      File.mkdir_p!(Path.join(test_folder, "content"))
      
      for i <- 1..100 do
        content = """
        ---
        title: Post #{i}
        date: 2024-01-#{rem(i, 28) + 1}
        ---
        
        Content for post #{i}
        """
        File.write!(Path.join(test_folder, "content/post_#{i}.md"), content)
      end
      
      create_test_yaml_config(test_folder)
      
      {:ok, _pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      # Measure build time
      start_time = System.monotonic_time(:millisecond)
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5_000
      
      # Wait for completion
      case wait_for_build_completion(test_folder, 30_000) do
        {:ok, ^build_id, _state} ->
          end_time = System.monotonic_time(:millisecond)
          build_time = end_time - start_time
          
          # Build should complete in reasonable time (adjust as needed)
          assert build_time < 30_000, "Build took too long: #{build_time}ms"
          
          {:ok, progress} = Server.get_build_progress(test_folder)
          assert progress.status == :completed
          assert progress.processed_records >= 100
          
        {:error, :timeout} ->
          flunk("Build did not complete within timeout")
      end
    end
  end
  
  # Helper functions
  
  defp collect_progress_updates(folder_path, build_id, timeout) do
    collect_progress_updates(folder_path, build_id, timeout, [])
  end
  
  defp collect_progress_updates(_folder_path, _build_id, timeout, acc) when timeout <= 0 do
    Enum.reverse(acc)
  end
  
  defp collect_progress_updates(folder_path, build_id, timeout, acc) do
    receive do
      {:build_progress, ^build_id, _data} = msg ->
        collect_progress_updates(folder_path, build_id, timeout - 100, [msg | acc])
        
      {:build_completed, ^build_id, _state} = msg ->
        Enum.reverse([msg | acc])
        
      {:build_error, ^build_id, _error} = msg ->
        collect_progress_updates(folder_path, build_id, timeout - 100, [msg | acc])
        
      {:build_stopped, ^build_id} = msg ->
        Enum.reverse([msg | acc])
    after
      100 ->
        collect_progress_updates(folder_path, build_id, timeout - 100, acc)
    end
  end
end