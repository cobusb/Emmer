defmodule Emmer.Builder.BuildPipeline do
  @moduledoc """
  The build pipeline for a project.
  """

  alias Handoff.Function

  # Step 1: Generate random data
generate_fn = %Function{
  id: :load_data,
  args: []
}

# Step 2: Filter data
filter_fn = %Function{
  id: :filter_data,
  args: [:load_data]
}

# determine spawns: 
transform_fn = %Function{
  id: :determine_spawns,
  args: [:filter_data]
}

# Step 4: Spawn subtasks
spawn_fn = %Function{
  id: :spawn_tasks,
  args: [:determine_spawns]
}

# Step 5: Format output
aggregate_fn = %Function{
  id: :format_output,
  args: [:aggregate_data, :filter_data], # Results passed in order to format_output_task/2
  code: &PipelineTasks.format_output_task/2,
  node: Node.self() # force the output to be collected at the calling node
}


end
