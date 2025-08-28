defmodule Emmer.Builder.ServerTest do
  use ExUnit.Case, async: false
  
  alias Emmer.Builder.Server
  alias Emmer.Builder.BuildLogger
  
  @test_folder "/tmp/emmer_test_#{:rand.uniform(1000000)}"
  @test_yaml_config """
  builder:
    verbose_logging: info
    source_folder: content
    ignore_folders:
      - node_modules
      - .git
  context:
    site_name: Test Site
  folder:
    output_type: static
  """
  
  setup do
    # Ensure the Registry is started
    case Registry.start_link(keys: :unique, name: Emmer.Builder.ServerRegistry) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
    
    # PubSub should already be started by the application
    # Just verify it's running
    case Process.whereis(Emmer.PubSub) do
      nil -> 
        # If not started, start it
        {:ok, _} = Supervisor.start_link([{Phoenix.PubSub, name: Emmer.PubSub}], strategy: :one_for_one)
      _pid -> 
        :ok
    end
    
    # Create test directory structure
    File.mkdir_p!(Path.join(@test_folder, "content"))
    File.write!(Path.join(@test_folder, "emmer.config.yaml"), @test_yaml_config)
    
    on_exit(fn ->
      # Clean up test directory
      File.rm_rf!(@test_folder)
      
      # Stop any running servers for this test folder
      case Registry.lookup(Emmer.Builder.ServerRegistry, @test_folder) do
        [{pid, _}] -> GenServer.stop(pid, :normal, 5000)
        [] -> :ok
      end
    end)
    
    {:ok, test_folder: @test_folder}
  end
  
  describe "start_link/1" do
    test "starts a new server with the given folder path", %{test_folder: test_folder} do
      assert {:ok, pid} = Server.start_link(test_folder)
      assert Process.alive?(pid)
      
      # Verify it's registered
      assert [{^pid, nil}] = Registry.lookup(Emmer.Builder.ServerRegistry, test_folder)
    end
    
    test "prevents duplicate servers for the same folder", %{test_folder: test_folder} do
      assert {:ok, pid1} = Server.start_link(test_folder)
      assert {:error, {:already_started, ^pid1}} = Server.start_link(test_folder)
    end
  end
  
  describe "full_build/1" do
    test "initiates a full build", %{test_folder: test_folder} do
      {:ok, _pid} = Server.start_link(test_folder)
      
      # Subscribe to build events
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      # Start the build
      assert :ok = Server.full_build(test_folder)
      
      # Should receive build_started event
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      assert build_id =~ ~r/^build_\d+_[a-f0-9]{8}$/
    end
    
    test "handles missing config file gracefully", %{test_folder: test_folder} do
      # Remove config file
      File.rm!(Path.join(test_folder, "emmer.config.yaml"))
      
      {:ok, _pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      assert :ok = Server.full_build(test_folder)
      
      # Build should start but fail
      assert_receive {:build_started, _build_id, ^test_folder}, 5000
      
      # Check that build failed
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.status == :failed
    end
  end
  
  describe "get_build_progress/1" do
    test "returns error when no build is running", %{test_folder: test_folder} do
      {:ok, _pid} = Server.start_link(test_folder)
      
      assert {:error, :not_found} = Server.get_build_progress(test_folder)
    end
    
    test "returns progress for active build", %{test_folder: test_folder} do
      {:ok, _pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      {:ok, progress} = Server.get_build_progress(test_folder)
      
      assert progress.id == build_id
      assert progress.status in [:building, :completed, :failed]
      assert progress.folders_count >= 0
      assert progress.agents_count >= 0
      assert progress.processors_count >= 0
      assert progress.errors_count >= 0
      assert progress.warnings_count >= 0
      assert progress.processed_records >= 0
      assert progress.total_records >= 0
      assert progress.progress_percentage >= 0
      assert progress.started_at != nil
    end
  end
  
  describe "stop_build/1" do
    test "stops an active build", %{test_folder: test_folder} do
      {:ok, _pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      # Stop the build
      assert :ok = Server.stop_build(test_folder)
      
      # Should receive build_stopped event
      assert_receive {:build_stopped, ^build_id}, 5000
      
      # Verify build status
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.status == :stopped
    end
    
    test "handles stop when no build is running", %{test_folder: test_folder} do
      {:ok, _pid} = Server.start_link(test_folder)
      
      # Should not crash
      assert :ok = Server.stop_build(test_folder)
    end
  end
  
  describe "build progress tracking" do
    test "tracks folder progress", %{test_folder: test_folder} do
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      # Start build
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      # Simulate folder events
      send(pid, {:build_progress, build_id, %{type: :folder_started, folder: "folder1"}})
      send(pid, {:build_progress, build_id, %{type: :folder_started, folder: "folder2"}})
      
      # Give it time to process
      :timer.sleep(100)
      
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.folders_count == 2
    end
    
    test "prevents duplicate folder tracking", %{test_folder: test_folder} do
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      # Send duplicate folder_started events
      send(pid, {:build_progress, build_id, %{type: :folder_started, folder: "folder1"}})
      send(pid, {:build_progress, build_id, %{type: :folder_started, folder: "folder1"}})
      
      :timer.sleep(100)
      
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.folders_count == 1
    end
    
    test "tracks agent creation", %{test_folder: test_folder} do
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      # Simulate agent creation
      send(pid, {:build_progress, build_id, %{type: :agent_created, agent: "agent1"}})
      send(pid, {:build_progress, build_id, %{type: :agent_created, agent: "agent2"}})
      
      :timer.sleep(100)
      
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.agents_count == 2
    end
    
    test "tracks processor creation", %{test_folder: test_folder} do
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      # Simulate processor creation
      send(pid, {:build_progress, build_id, %{type: :processor_started, processor: "proc1"}})
      send(pid, {:build_progress, build_id, %{type: :processor_started, processor: "proc2"}})
      
      :timer.sleep(100)
      
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.processors_count == 2
    end
    
    test "tracks record processing", %{test_folder: test_folder} do
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      # Set total records
      send(pid, {:build_progress, build_id, %{type: :total_records, count: 100}})
      
      # Process some records
      send(pid, {:build_progress, build_id, %{type: :record_processed, count: 25}})
      send(pid, {:build_progress, build_id, %{type: :record_processed, count: 25}})
      
      :timer.sleep(100)
      
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.total_records == 100
      assert progress.processed_records == 50
      assert progress.progress_percentage == 50.0
    end
    
    test "tracks warnings and errors", %{test_folder: test_folder} do
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      # Add warnings
      send(pid, {:build_progress, build_id, %{type: :warning, message: "Warning 1"}})
      send(pid, {:build_progress, build_id, %{type: :warning, message: "Warning 2"}})
      
      # Add error
      send(pid, {:build_error, build_id, "Error 1"})
      
      :timer.sleep(100)
      
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.warnings_count == 2
      assert progress.errors_count == 1
    end
  end
  
  describe "build completion" do
    test "completes build when all folders are done", %{test_folder: test_folder} do
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      Phoenix.PubSub.subscribe(Emmer.PubSub, "build_completion:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      # Simulate folder lifecycle
      send(pid, {:build_progress, build_id, %{type: :folder_started, folder: "folder1"}})
      send(pid, {:build_progress, build_id, %{type: :folder_started, folder: "folder2"}})
      
      :timer.sleep(100)
      
      # Complete folders
      send(pid, {:build_progress, build_id, %{type: :folder_completed, folder: "folder1"}})
      send(pid, {:build_progress, build_id, %{type: :folder_completed, folder: "folder2"}})
      
      # Should receive build completed
      assert_receive {:build_completed, ^build_id, final_state}, 5000
      assert final_state.status == :completed
    end
    
    test "does not complete if no folders were processed", %{test_folder: test_folder} do
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      # No folders started, so even with 0 active folders, build shouldn't complete
      {:ok, state} = :sys.get_state(pid)
      assert state.active_folder_count == 0
      assert length(state.folders) == 0
      
      # Build should not be marked as complete
      refute_receive {:build_completed, _, _}, 1000
    end
  end
  
  describe "error handling" do
    test "handles build errors gracefully", %{test_folder: test_folder} do
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      # Send multiple errors
      for i <- 1..7 do
        send(pid, {:build_error, build_id, "Error #{i}"})
      end
      
      :timer.sleep(100)
      
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.errors_count == 7
      # Build should fail after 5 errors
      assert progress.status == :failed
    end
    
    test "handles invalid yaml config", %{test_folder: test_folder} do
      # Write invalid YAML
      File.write!(Path.join(test_folder, "emmer.config.yaml"), "invalid: yaml: content:")
      
      {:ok, _pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, _build_id, ^test_folder}, 5000
      
      # Build should fail
      :timer.sleep(100)
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.status == :failed
      assert progress.errors_count > 0
    end
  end
  
  describe "cleanup_old_processes/1" do
    test "cleans up old processes", %{test_folder: test_folder} do
      {:ok, _pid} = Server.start_link(test_folder)
      
      # Should not crash even if no processes to clean
      assert :ok = Server.cleanup_old_processes(test_folder)
    end
  end
  
  
  describe "concurrent builds" do
    test "handles multiple build requests gracefully", %{test_folder: test_folder} do
      {:ok, _pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      # Start first build
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id1, ^test_folder}, 5000
      
      # Try to start second build while first is running
      Server.full_build(test_folder)
      
      # Should still be the same build or a new one (implementation dependent)
      # Important thing is it shouldn't crash
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.id != nil
    end
  end
  
  describe "state persistence" do
    test "maintains state across progress updates", %{test_folder: test_folder} do
      {:ok, pid} = Server.start_link(test_folder)
      Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
      
      Server.full_build(test_folder)
      assert_receive {:build_started, build_id, ^test_folder}, 5000
      
      # Send various progress updates
      send(pid, {:build_progress, build_id, %{type: :folder_started, folder: "folder1"}})
      send(pid, {:build_progress, build_id, %{type: :agent_created, agent: "agent1"}})
      send(pid, {:build_progress, build_id, %{type: :total_records, count: 50}})
      send(pid, {:build_progress, build_id, %{type: :record_processed, count: 10}})
      
      :timer.sleep(100)
      
      # Verify all state is maintained
      {:ok, progress} = Server.get_build_progress(test_folder)
      assert progress.folders_count == 1
      assert progress.agents_count == 1
      assert progress.total_records == 50
      assert progress.processed_records == 10
    end
  end
end