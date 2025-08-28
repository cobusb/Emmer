# Wait Processor Example

This example demonstrates how to use the `Emmer.Processor.Wait` processor to introduce delays in your build process.

## Overview

The Wait processor is useful for:
- Testing build timing and performance
- Debugging race conditions or timing issues
- Simulating slow operations in development
- Adding cooldown periods after intensive operations
- Rate limiting when calling external APIs or services

## Basic Usage

### As a Regular Processor (Per File)

When used as a regular processor, the Wait processor will pause for the specified number of seconds for **each file** that matches the filter.

```yaml
config:
  processors:
    - name: "slow_html_processing"
      module: "Emmer.Processor.Wait"
      seconds: 1.5
      message: "Simulating slow HTML processing"
      filter:
        regex: "\.html$"
```

**Result:** Waits 1.5 seconds for each HTML file processed.

### As a Post-Processor (Once Per Build)

When used as a post-processor, the Wait processor will pause for the specified number of seconds **once** after all files have been processed.

```yaml
config:
  processors:
    - name: "build_cooldown"
      module: "Emmer.Processor.Wait"
      post_processor: true
      seconds: 3
      message: "Build complete - cooling down"
```

**Result:** Waits 3 seconds once at the end of the build process.

## Configuration Options

| Option | Required | Type | Description |
|--------|----------|------|-------------|
| `seconds` | Yes | Number/String | Number of seconds to wait (supports decimals) |
| `message` | No | String | Custom message to log (default: "Waiting...") |
| `post_processor` | No | Boolean | If true, runs once at end; if false/missing, runs per file |
| `filter` | No | Object | Standard Emmer filter to select which files to process |

## Examples

### 1. Testing Build Performance

Add delays to see how your build process handles slow operations:

```yaml
config:
  processors:
    # Regular processing
    - name: "html"
      module: "Emmer.Processor.YamlLiquidStaticSite"
      filter:
        regex: "\.(html|md)$"
      output_dir: "dist"

    # Simulate slow image processing
    - name: "slow_images"
      module: "Emmer.Processor.Wait"
      seconds: 0.5
      message: "Simulating image optimization"
      filter:
        regex: "\.(jpg|png|gif)$"

    # Final build cooldown
    - name: "final_wait"
      module: "Emmer.Processor.Wait"
      post_processor: true
      seconds: 2
      message: "Build complete - final cooldown"
```

### 2. API Rate Limiting Simulation

Simulate rate-limited API calls:

```yaml
config:
  processors:
    - name: "api_calls"
      module: "Emmer.Processor.Wait"
      seconds: 1
      message: "Rate limiting API calls"
      filter:
        regex: "\.json$"
```

### 3. Development Debugging

Add strategic pauses to debug timing issues:

```yaml
config:
  processors:
    # Process markdown files
    - name: "markdown"
      module: "Emmer.Processor.YamlLiquidStaticSite"
      filter:
        regex: "\.md$"

    # Wait before asset processing to debug race conditions
    - name: "debug_pause"
      module: "Emmer.Processor.Wait"
      post_processor: true
      seconds: 1
      message: "Debug pause before assets"

    # Process assets
    - name: "assets"
      module: "Emmer.Processor.AssetBuilder"
      post_processor: true
      builder: "Emmer.AssetBuilder.TailwindEsbuild"
      builder_config:
        css_entry: "styles/main.css"
```

### 4. Mixed Usage

Combine regular and post-processor waits:

```yaml
config:
  processors:
    # Wait per HTML/Markdown file (simulating slow template rendering)
    - name: "slow_templates"
      module: "Emmer.Processor.Wait"
      seconds: 0.2
      message: "Slow template rendering"
      filter:
        regex: "\.(html|md)$"

    # Actual HTML/Markdown processing
    - name: "html"
      module: "Emmer.Processor.YamlLiquidStaticSite"
      filter:
        regex: "\.(html|md)$"
      output_dir: "dist"

    # Wait once after all processing
    - name: "final_cooldown"
      module: "Emmer.Processor.Wait"
      post_processor: true
      seconds: 5
      message: "All done - taking a break"
```

## Flexible Time Specifications

The `seconds` parameter accepts various formats:

```yaml
# Integer seconds
seconds: 3

# Decimal seconds
seconds: 1.5

# String format (useful in YAML)
seconds: "2.25"

# Very short waits
seconds: 0.1
```

## Expected Log Output

### Regular Processor
```
[info] build_123 Wait (index.html): Simulating slow processing - waiting 1.5 seconds
[debug] build_123 Wait: Sleeping for 1500ms
[debug] build_123 Wait: Sleep completed
[debug] build_123 Wait processor completed
```

### Post-Processor
```
[info] build_123 Wait (post-processor): Build complete - cooling down - waiting 3 seconds
[debug] build_123 Wait: Sleeping for 3000ms
[debug] build_123 Wait: Sleep completed
[debug] build_123 Wait processor completed
```

## Error Handling

The processor validates configuration and provides helpful error messages:

### Missing seconds configuration:
```
[error] build_123 Wait processor configuration error: Missing required 'seconds' configuration
```

### Invalid seconds value:
```
[error] build_123 Wait processor configuration error: Invalid seconds value: 'abc'. Must be a positive number.
```

### Negative seconds:
```
[error] build_123 Wait processor configuration error: Invalid seconds value: -1. Must be a positive number.
```

## Tips and Best Practices

1. **Use small waits for regular processors** - Large delays per file can make builds very slow
2. **Post-processors are better for longer waits** - Use when you need a single delay
3. **Combine with filters** - Target specific file types to avoid unnecessary delays
4. **Use meaningful messages** - Help identify what each wait is simulating
5. **Decimal precision** - Use decimal seconds (e.g., 0.1) for fine-grained timing
6. **Development vs Production** - Consider using different configs or environment variables
7. **Debug timing issues** - Strategic waits can help identify race conditions

## Practical Use Cases

### Load Testing Simulation
```yaml
- name: "simulate_load"
  module: "Emmer.Processor.Wait"
  seconds: 0.5
  message: "Simulating server load"
```

### Asset Processing Delay
```yaml
- name: "asset_delay"
  module: "Emmer.Processor.Wait"
  post_processor: true
  seconds: 2
  message: "Allowing assets to settle"
```

### File System Sync Wait
```yaml
- name: "fs_sync_wait"
  module: "Emmer.Processor.Wait"
  post_processor: true
  seconds: 1
  message: "Waiting for file system sync"
```

This processor provides a simple but powerful way to introduce controlled delays in your build process for testing, debugging, and simulation purposes.
