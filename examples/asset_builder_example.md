# Asset Builder Examples

This document shows how to use the dynamic asset builder system in Emmer.

## Basic Tailwind + esbuild Setup

### Directory Structure
```
my-site/
├── content/
│   ├── styles/
│   │   └── main.css
│   ├── js/
│   │   └── main.js
│   └── folder.yaml
├── emmer.config.yaml
└── dist/ (generated)
```

### Configuration Files

**emmer.config.yaml**
```yaml
builder:
  verbose_logging: "info"
  source_folder: "content"

context:
  site_name: "My Awesome Site"
  author: "John Doe"

folder:
  record_loader: "Emmer.RecordLoader.FileLoader"
  config:
    processors:
      # Regular processor for HTML files
      - name: "html"
        module: "Emmer.Processor.StandardLiquid"
        filter:
          regex: ".html$"
        output_dir: "dist"

      # Post-processor for assets (runs once after all files)
      - name: "assets"
        module: "Emmer.Processor.AssetBuilder"
        post_processor: true  # This makes it run once at the end
        builder: "Emmer.AssetBuilder.TailwindEsbuild"
        builder_config:
          css_entry: "styles/main.css"
          js_entry: "js/main.js"
          plugins: ["daisyui", "@tailwindcss/typography"]
          theme:
            colors:
              primary: "#3b82f6"
              secondary: "#10b981"
        output_subdir: "assets"  # Deprecated, use output_dir instead
```

**content/folder.yaml**
```yaml
record_loader: "Emmer.RecordLoader.FileLoader"
config:
  processors:
    # Regular processors for content files
    - name: "markdown"
      module: "Emmer.Processor.StandardLiquid"
      filter:
        regex: ".md$"
      output_dir: "dist"

    # Post-processor for building assets once
    - name: "assets"
      module: "Emmer.Processor.AssetBuilder"
      post_processor: true  # Important: Makes this run once after all files
      builder: "Emmer.AssetBuilder.TailwindEsbuild"
      output_dir: "dist/assets"  # Output to project_root/dist/assets/
      builder_config:
        css_entry: "styles/main.css"
        js_entry: "js/main.js"
        content_paths:  # Optional - specify which files Tailwind should scan
          - "../dist/**/*.html"     # Scan processed HTML in dist folder
          - "**/*.{js,ts,jsx,tsx}"  # Scan source JS/TS files
        minify: true
        sourcemap: false
```

**content/styles/main.css**
```css
@import "tailwindcss/base";
@import "tailwindcss/components";
@import "tailwindcss/utilities";

/* Custom styles */
.hero {
  @apply bg-gradient-to-r from-primary to-secondary text-white;
}
```

**content/js/main.js**
```javascript
// Modern JavaScript with ES6+ features
import { createApp } from 'vue'; // if using Vue
// or any other modern JS

console.log('Site loaded!');

// Example: Dynamic theme switching
const themeToggle = document.querySelector('[data-theme-toggle]');
if (themeToggle) {
  themeToggle.addEventListener('click', () => {
    document.documentElement.setAttribute('data-theme',
      document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark'
    );
  });
}
```

## React with Vite Setup

### Directory Structure
```
react-site/
├── content/
│   ├── src/
│   │   ├── main.jsx
│   │   ├── App.jsx
│   │   └── components/
│   ├── package.json
│   ├── index.html
│   └── folder.yaml
└── dist/ (generated)
```

**content/folder.yaml**
```yaml
record_loader: "Emmer.RecordLoader.FileLoader"
config:
  processors:
    # Post-processor for React app
    - name: "react-app"
      module: "Emmer.Processor.AssetBuilder"
      post_processor: true  # Runs once after all files are processed
      builder: "Emmer.AssetBuilder.ReactVite"
      builder_config:
        entry: "src/main.jsx"
        outDir: "dist"
        base: "/"
        minify: true
        sourcemap: true
```

**content/package.json**
```json
{
  "name": "my-react-site",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.15",
    "@types/react-dom": "^18.2.7",
    "@vitejs/plugin-react": "^4.0.3",
    "vite": "^4.4.5"
  }
}
```

**content/src/main.jsx**
```jsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
```

## Creating Custom Asset Builders

### Custom PostCSS Builder Example

**lib/my_app/asset_builder/postcss_builder.ex**
```elixir
defmodule MyApp.AssetBuilder.PostcssBuilder do
  @behaviour Emmer.AssetBuilder.Behaviour

  alias Emmer.Builder.BuildLogger

  def build(source_path, output_path, config, context) do
    input_css = Path.join(source_path, config["entry"])
    output_css = Path.join(output_path, config["output"] || "main.css")

    File.mkdir_p!(Path.dirname(output_css))

    # Create PostCSS config
    postcss_config = create_postcss_config(config)
    temp_config = Path.join(System.tmp_dir!(), "postcss-#{unique_id()}.config.js")
    File.write!(temp_config, postcss_config)

    args = ["postcss", input_css, "-o", output_css, "--config", temp_config]

    case System.cmd("npx", args, cd: source_path, stderr_to_stdout: true) do
      {_output, 0} ->
        File.rm(temp_config)
        {:ok, [output_css]}
      {error, _} ->
        File.rm(temp_config)
        {:error, "PostCSS build failed: #{error}"}
    end
  end

  def supported_extensions, do: [".css", ".pcss"]

  def validate_config(config) do
    case Map.has_key?(config, "entry") do
      true -> :ok
      false -> {:error, "Missing 'entry' key"}
    end
  end

  def cleanup(temp_files) do
    Enum.each(temp_files, &File.rm/1)
    :ok
  end

  defp create_postcss_config(config) do
    plugins = config["plugins"] || ["autoprefixer"]

    """
    module.exports = {
      plugins: #{Jason.encode!(plugins)}
    }
    """
  end

  defp unique_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end
end
```

**Usage in folder.yaml:**
```yaml
processors:
  - name: "styles"
    module: "Emmer.Processor.AssetBuilder"
    post_processor: true  # Run once after all files are processed
    builder: "MyApp.AssetBuilder.PostcssBuilder"
    builder_config:
      entry: "styles/main.css"
      output: "bundle.css"
      plugins: ["autoprefixer", "cssnano"]
```

## Output Directory Configuration

The AssetBuilder processor now supports an `output_dir` configuration that works similarly to the FileCopy processor. The output directory is resolved relative to the project root (where `emmer.config.yaml` is located).

**Example Configuration:**
```yaml
processors:
  - name: "assets"
    module: "Emmer.Processor.AssetBuilder"
    post_processor: true
    builder: "Emmer.AssetBuilder.TailwindEsbuild"
    output_dir: "dist/assets"  # Relative to project root
    builder_config:
      css_entry: "styles/main.css"
```

**Path Resolution:**
- `output_dir: "dist/assets"` → `{project_root}/dist/assets/`
- `output_dir: "../build/assets"` → `{project_root}/../build/assets/`
- `output_dir: "/tmp/assets"` → `/tmp/assets/` (absolute path)

**Generated Files:**
- CSS: `{output_dir}/main.css`
- JS: `{output_dir}/main.js` (if configured)

**Backward Compatibility:**
If `output_dir` is not specified, the processor falls back to the old behavior using `output_subdir` (defaults to "assets") relative to the source path.

## Multi-Framework Site Example

For sites that need multiple asset builders:

**content/folder.yaml**
```yaml
record_loader: "Emmer.RecordLoader.FileLoader"
config:
  processors:
    # Regular processors for content files
    - name: "html"
      module: "Emmer.Processor.StandardLiquid"
      filter:
        regex: ".html$"
      output_dir: "dist"

    # Post-processors for assets (run once at the end)
    - name: "main-styles"
      module: "Emmer.Processor.AssetBuilder"
      post_processor: true  # Important!
      builder: "Emmer.AssetBuilder.TailwindEsbuild"
      builder_config:
        css_entry: "styles/main.css"
        js_entry: "js/main.js"

    # Admin panel with React (also a post-processor)
    - name: "admin-app"
      module: "Emmer.Processor.AssetBuilder"
      post_processor: true  # Important!
      builder: "Emmer.AssetBuilder.ReactVite"
      builder_config:
        entry: "admin/src/main.jsx"
        outDir: "admin-dist"
        base: "/admin/"
```

## Asset Builder Discovery

You can programmatically discover available builders:

```elixir
# List all available builders
builders = Emmer.AssetBuilder.Registry.list_available_builders()
# [
#   %{
#     name: "TailwindEsbuild",
#     module: Emmer.AssetBuilder.TailwindEsbuild,
#     supported_extensions: [".css", ".js", ".ts"]
#   },
#   %{
#     name: "ReactVite",
#     module: Emmer.AssetBuilder.ReactVite,
#     supported_extensions: [".js", ".jsx", ".ts", ".tsx", ".css"]
#   }
# ]

# Find specific builder
{:ok, builder_info} = Emmer.AssetBuilder.Registry.find_builder("TailwindEsbuild")

# Validate config before using
:ok = Emmer.Processor.AssetBuilder.validate_builder_config(
  "Emmer.AssetBuilder.TailwindEsbuild",
  %{"css_entry" => "main.css", "js_entry" => "main.js"}
)
```

## Important: Post-Processor Pattern

Asset builders must be configured as **post-processors** using the `post_processor: true` flag. This ensures they:
- Run **once** after all files are processed
- Receive the correct source folder path
- Don't get applied to individual files (like images or HTML)

### Key Differences:

**Regular Processor** (runs on each file):
```yaml
- name: "html"
  module: "Emmer.Processor.StandardLiquid"
  filter:
    regex: ".html$"
```

**Post-Processor** (runs once at the end):
```yaml
- name: "assets"
  module: "Emmer.Processor.AssetBuilder"
  post_processor: true  # ← This is crucial!
  builder: "Emmer.AssetBuilder.TailwindEsbuild"
```

## Tips and Best Practices

1. **Always use post_processor: true** for asset builders to prevent them from running on every file
2. **Dependencies**: Make sure required tools (Node.js, npm, specific packages) are installed
3. **Error Handling**: Asset builders provide detailed error messages
4. **Performance**: Builders clean up temporary files automatically
5. **Development**: Use `sourcemap: true` and `minify: false` during development
6. **Production**: Enable minification and disable sourcemaps for production builds
7. **Multiple Builders**: You can use different builders for different parts of your site
8. **Custom Builders**: Implement the behaviour with the correct signature: `build/4`
9. **Path Resolution**: CSS/JS entry paths are resolved relative to the source folder

This system provides maximum flexibility while maintaining a clean, configuration-driven approach to asset building in static site generation.
