# Emmer DAG Implementation - Full Replacement Strategy

## Overview
Complete replacement of the current hierarchical process tree with a DAG-based architecture using Handoff.

## Current System Components to Replace

### 1. **Builder.Server** → `Emmer.DAG.BuildManager`
- Manages DAG construction and execution
- Tracks build progress through DAG node completion
- Handles build lifecycle (start, stop, status)

### 2. **FolderProcess** → DAG Nodes
- Each folder becomes a node in the DAG
- Folder dependencies explicitly defined
- No more recursive Task spawning

### 3. **Processor.Dispatcher** → Built into DAG execution
- Handoff handles task dispatching
- Dependencies ensure correct execution order
- Resource management built-in

## New Architecture

### Core Modules

```elixir
defmodule Emmer.DAG.BuildManager do
  @moduledoc """
  Replaces Builder.Server - manages DAG-based builds
  """
  use GenServer
  
  defstruct [
    :dag_id,
    :dag,
    :status,
    :progress,
    :started_at,
    :root_path
  ]
  
  def start_build(folder_path) do
    # 1. Load configuration
    # 2. Build DAG from folder structure
    # 3. Execute DAG
    # 4. Track progress
  end
end

defmodule Emmer.DAG.Node do
  @moduledoc """
  Represents a processing unit in the DAG
  """
  defstruct [
    :id,
    :type,           # :folder | :record_loader | :processor | :post_processor
    :path,           # For folders and files
    :module,         # Processing module
    :config,         # Configuration
    :dependencies,   # List of node IDs
    :resources,      # Resource requirements
    :priority        # Execution priority
  ]
end

defmodule Emmer.DAG.Builder do
  @moduledoc """
  Constructs DAG from folder structure and configurations
  """
  
  def build(root_path, config) do
    dag = Handoff.new()
    
    # Build complete dependency graph
    {dag, nodes} = analyze_project_structure(root_path, config)
    
    # Add all nodes with proper dependencies
    register_nodes(dag, nodes)
  end
  
  defp analyze_project_structure(root_path, config) do
    # 1. Scan all folders
    # 2. Load all configurations
    # 3. Create nodes for:
    #    - Each folder
    #    - Each record loader
    #    - Each processor
    #    - Each post-processor
    # 4. Establish dependencies
  end
end

defmodule Emmer.DAG.Executor do
  @moduledoc """
  Executes DAG nodes as Handoff functions
  """
  
  def execute_node(node, context) do
    case node.type do
      :folder -> process_folder_node(node, context)
      :record_loader -> process_loader_node(node, context)
      :processor -> process_processor_node(node, context)
      :post_processor -> process_post_processor_node(node, context)
    end
  end
end
```

## Implementation Steps

### Step 1: Add Handoff Dependency
```elixir
# mix.exs
defp deps do
  [
    {:handoff, "~> 0.1.0"},
    # ... other deps
  ]
end
```

### Step 2: Create New DAG Modules

#### `lib/emmer/dag/build_manager.ex`
```elixir
defmodule Emmer.DAG.BuildManager do
  use GenServer
  require Logger
  
  alias Emmer.DAG.{Builder, Executor, ProgressTracker}
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def start_build(folder_path) do
    GenServer.call(__MODULE__, {:start_build, folder_path})
  end
  
  def handle_call({:start_build, folder_path}, _from, state) do
    build_id = generate_build_id()
    
    # Load configuration
    {:ok, config} = load_configuration(folder_path)
    
    # Build DAG
    dag = Builder.build(folder_path, config, build_id)
    
    # Start execution
    {:ok, execution_ref} = Executor.execute(dag, self())
    
    new_state = %{
      build_id: build_id,
      dag: dag,
      execution_ref: execution_ref,
      status: :running,
      folder_path: folder_path
    }
    
    {:reply, {:ok, build_id}, new_state}
  end
end
```

#### `lib/emmer/dag/builder.ex`
```elixir
defmodule Emmer.DAG.Builder do
  alias Emmer.DAG.Node
  
  def build(root_path, config, build_id) do
    # Initialize Handoff DAG
    dag = Handoff.new()
    
    # Build node graph
    nodes = build_node_graph(root_path, config, build_id)
    
    # Register nodes with Handoff
    Enum.reduce(nodes, dag, fn node, dag_acc ->
      function = create_node_function(node)
      Handoff.add_function(dag_acc, node.id, function, node.dependencies)
    end)
  end
  
  defp build_node_graph(root_path, config, build_id) do
    # Scan entire project structure upfront
    all_folders = scan_folders(root_path, config)
    
    # Create nodes for each processing unit
    nodes = Enum.flat_map(all_folders, fn folder_path ->
      create_nodes_for_folder(folder_path, config, build_id)
    end)
    
    # Establish cross-folder dependencies if needed
    add_cross_dependencies(nodes, config)
  end
  
  defp create_node_function(node) do
    fn ->
      Emmer.DAG.Executor.execute_node(node)
    end
  end
end
```

#### `lib/emmer/dag/executor.ex`
```elixir
defmodule Emmer.DAG.Executor do
  def execute(dag, callback_pid) do
    # Configure Handoff execution
    opts = [
      on_complete: fn result -> 
        send(callback_pid, {:dag_complete, result})
      end,
      on_error: fn error ->
        send(callback_pid, {:dag_error, error})
      end,
      on_progress: fn node_id, status ->
        send(callback_pid, {:node_progress, node_id, status})
      end
    ]
    
    # Execute DAG
    Handoff.execute_local(dag, opts)
  end
  
  def execute_node(%Node{type: :folder} = node) do
    # Folder node mainly serves as a dependency checkpoint
    {:ok, :folder_ready}
  end
  
  def execute_node(%Node{type: :record_loader} = node) do
    # Initialize record loader
    {:ok, agent} = init_record_loader(node.module, node.config)
    {:ok, agent}
  end
  
  def execute_node(%Node{type: :processor} = node) do
    # Execute processor with data from its dependencies
    deps_data = Handoff.get_dependency_results(node.dependencies)
    apply(node.module, :start_link, [deps_data, node.config])
  end
  
  def execute_node(%Node{type: :post_processor} = node) do
    # Execute post-processor after all dependencies complete
    context = gather_context_from_dependencies(node.dependencies)
    apply(node.module, :build, [context, node.config])
  end
end
```

### Step 3: Configuration Changes

#### Enhanced YAML Configuration
```yaml
# emmer.config.yaml
builder:
  source_folder: "content"
  verbose_logging: "info"
  ignore_folders: ["node_modules", ".git", "dist"]
  
  # DAG-specific settings
  dag:
    max_parallel: 10
    resource_limits:
      memory_mb: 2048
      cpu_cores: 4
    visualization: true  # Generate DAG visualization

# folder.yaml with explicit dependencies
config:
  dependencies:
    # Define cross-folder dependencies
    - source: "content/blog"
      target: "content/assets"
      type: "requires"  # blog requires assets to be processed first
  
  processors:
    - id: "markdown_main"
      name: "Markdown Processor"
      module: "Emmer.Processor.MarkdownLiquid"
      dependencies: []  # Can start immediately
      
    - id: "images_main"  
      name: "Image Processor"
      module: "Emmer.Processor.Image"
      dependencies: []  # Can run in parallel with markdown
      
    - id: "assets_main"
      name: "Asset Builder"
      module: "Emmer.Processor.AssetBuilder"
      dependencies: ["markdown_main", "images_main"]
      post_processor: true
      
    - id: "search_index"
      name: "Search Index Builder"
      module: "Emmer.Processor.SearchIndex"
      dependencies: ["assets_main"]
      post_processor: true
```

### Step 4: Migration Path

#### Phase 1: Remove Old Modules (Week 1)
1. Remove `Emmer.Builder.Server`
2. Remove `Emmer.Builder.FolderProcess`
3. Remove `Emmer.Processor.Dispatcher`
4. Update `Emmer.Builder.Supervisor` to start `DAG.BuildManager`

#### Phase 2: Implement DAG Core (Week 1-2)
1. Implement `Emmer.DAG.BuildManager`
2. Implement `Emmer.DAG.Builder`
3. Implement `Emmer.DAG.Executor`
4. Implement `Emmer.DAG.Node`

#### Phase 3: Update Processors (Week 2)
1. Ensure all processors are DAG-compatible
2. Update processor interfaces if needed
3. Add resource requirement declarations

#### Phase 4: Testing & Optimization (Week 3)
1. Comprehensive testing suite
2. Performance benchmarking
3. DAG visualization tooling
4. Resource monitoring

### Step 5: Update Supervision Tree

```elixir
defmodule Emmer.Application do
  def start(_type, _args) do
    children = [
      # Remove old supervisors
      # {Emmer.Builder.Supervisor, []},
      
      # Add new DAG supervisors
      {Emmer.DAG.BuildManager, []},
      {Task.Supervisor, name: Emmer.DAG.TaskSupervisor},
      
      # Keep these
      {Registry, keys: :unique, name: Emmer.DAG.Registry},
      {Phoenix.PubSub, name: Emmer.PubSub},
      EmmerWeb.Telemetry,
      EmmerWeb.Endpoint
    ]
    
    opts = [strategy: :one_for_one, name: Emmer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Benefits of Full Replacement

1. **Simplified Mental Model**: Single DAG instead of nested process trees
2. **Better Performance**: Optimal parallelization based on dependencies
3. **Clearer Dependencies**: Explicit rather than implicit ordering
4. **Resource Management**: Built-in resource constraints
5. **Distributed Ready**: Easy to scale across nodes
6. **Visualization**: Can generate and display DAG structure
7. **Deterministic**: Same inputs always produce same execution order

## Potential Challenges

1. **Learning Curve**: Team needs to understand DAG concepts
2. **Debugging**: Different debugging approach needed
3. **Configuration**: More explicit configuration required
4. **Testing**: Need new testing strategies for DAG

## Monitoring & Debugging

### DAG Visualization
```elixir
defmodule Emmer.DAG.Visualizer do
  def to_dot(dag) do
    # Generate GraphViz DOT format
  end
  
  def to_mermaid(dag) do
    # Generate Mermaid diagram
  end
  
  def live_view(dag_id) do
    # Real-time execution visualization
  end
end
```

### Progress Tracking
```elixir
defmodule Emmer.DAG.ProgressTracker do
  def calculate_progress(dag, completed_nodes) do
    total = Handoff.node_count(dag)
    completed = length(completed_nodes)
    percentage = (completed / total) * 100
    
    %{
      total_nodes: total,
      completed_nodes: completed,
      percentage: percentage,
      estimated_remaining: estimate_remaining_time(dag, completed_nodes)
    }
  end
end
```

## Conclusion

Replacing the current process tree with a DAG architecture will:
- Simplify the codebase by removing recursive folder processing
- Improve performance through optimal parallelization
- Make dependencies explicit and manageable
- Enable future distributed processing capabilities
- Provide better visibility into build process

The implementation requires approximately 3 weeks of development with careful testing to ensure feature parity with the current system.