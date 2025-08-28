ExUnit.start()

# Load support files
Code.require_file("test/support/test_helpers.exs")

# Start necessary applications
Application.ensure_all_started(:phoenix_pubsub)

# Create test database
case Emmer.Repo.start_link() do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
  {:error, _} = error -> raise "Failed to start Repo: #{inspect(error)}"
end

# Clean up test files after tests
ExUnit.after_suite(fn _ ->
  # Clean up any test build directories
  test_dirs = Path.wildcard("/tmp/emmer_test_*") ++ Path.wildcard("/tmp/emmer_stress_*") ++ Path.wildcard("/tmp/emmer_property_*")
  Enum.each(test_dirs, &File.rm_rf!/1)
end)