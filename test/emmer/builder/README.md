# Emmer Builder Server Test Suite

This directory contains comprehensive tests for the `Emmer.Builder.Server` module.

## Test Files

### server_test.exs
Core unit tests covering:
- Server lifecycle (start_link, stop)
- Build operations (full_build, partial_build, stop_build)
- Progress tracking and reporting
- State management
- Error handling
- Event broadcasting via Phoenix.PubSub

### server_integration_test.exs
Integration tests covering:
- Full build workflows with real file structures
- Concurrent builds on multiple folders
- Build recovery from crashes
- Memory and performance characteristics
- File system error handling

### server_stress_test.exs
Stress and load tests covering:
- Rapid start/stop cycles
- Many concurrent progress updates
- Large folder structures
- Resource cleanup after multiple builds
- Memory usage under load

### server_property_test.exs
Property-based tests verifying invariants:
- Build ID uniqueness and format
- Valid state transitions
- Monotonic progress values
- Concurrent operation consistency
- Error resilience
- Progress percentage bounds (0-100%)
- Non-negative counters

## Running Tests

Run all tests:
```bash
mix test
```

Run only unit tests:
```bash
mix test test/emmer/builder/server_test.exs
```

Run integration tests:
```bash
mix test --only integration
```

Run stress tests (may take longer):
```bash
mix test --only stress
```

Run property tests:
```bash
mix test --only property
```

Run with coverage:
```bash
mix test --cover
```

## Test Structure

Each test file follows a consistent structure:
1. Module setup with required aliases
2. Setup/teardown callbacks for test isolation
3. Grouped test cases using `describe` blocks
4. Helper functions at the bottom

## Key Testing Patterns

### Temporary Directories
Tests use unique temporary directories to avoid conflicts:
```elixir
@test_folder "/tmp/emmer_test_#{:rand.uniform(1000000)}"
```

### Phoenix.PubSub Subscriptions
Tests subscribe to PubSub topics to verify events:
```elixir
Phoenix.PubSub.subscribe(Emmer.PubSub, "builder:#{test_folder}")
assert_receive {:build_started, build_id, ^test_folder}, 5000
```

### State Inspection
Direct state inspection for detailed verification:
```elixir
{:ok, state} = :sys.get_state(pid)
assert state.active_folder_count == expected_count
```

### Async Safety
Most tests use `async: false` due to shared resources (Registry, PubSub).

## Common Issues and Solutions

### Registry Already Started
The test helper ensures registries are started only once.

### PubSub Timeouts
Increase timeout values if tests fail on slower systems:
```elixir
assert_receive {:build_started, _, _}, 10_000  # 10 seconds
```

### File System Cleanup
Tests automatically clean up temporary directories in `on_exit` callbacks.

## Adding New Tests

When adding new tests:
1. Use unique folder names to avoid conflicts
2. Clean up resources in `on_exit` callbacks
3. Subscribe to PubSub topics before triggering events
4. Use appropriate tags (`:integration`, `:stress`, `:property`)
5. Consider timeout requirements for longer operations