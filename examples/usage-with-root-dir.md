# Using Emmer with Separate Root Directory

This example shows how to use Emmer when your site content is in a separate directory from the Emmer project.

## Directory Structure

```
my-projects/
├── emmer/                    # Emmer project (where you run mix commands)
│   ├── lib/
│   ├── bin/
│   └── mix.exs
└── my-website/               # Your site content (separate from Emmer)
    ├── content/
    │   ├── home/
    │   │   ├── index.html
    │   │   └── index.yaml
    │   └── site.yaml
    ├── templates/
    │   └── layout.html
    ├── assets/
    │   └── css/
    └── package.json          # For CSS generation
```

## Building from Emmer Directory

### Using the Build Script

```bash
# From the emmer directory
cd emmer

# Build site in separate directory
./bin/build ../my-website

# Or with custom directories
./bin/build ../my-website content dist templates assets
```

### Using Mix Commands

```bash
# From the emmer directory
cd emmer

# Build with root directory
mix run -e 'SiteEmmer.main(["--root-dir", "../my-website", "--source-dir", "content", "--output-dir", "dist", "--templates-dir", "templates"])'

# Or using the build function directly
mix run -e 'SiteEmmer.build([root_dir: "../my-website", source_dir: "content", output_dir: "dist", templates_dir: "templates", verbose: true])'
```

### Using Watch Mode

```bash
# From the emmer directory
cd emmer

# Watch for changes in the separate site directory
mix run -e 'SiteEmmer.watch([root_dir: "../my-website", source_dir: "content", templates_dir: "templates"])'
```

## VS Code Extension Configuration

### Settings

In your VS Code workspace settings (`.vscode/settings.json`):

```json
{
  "emmer.rootDir": "../my-website",
  "emmer.sourceDir": "content",
  "emmer.outputDir": "dist",
  "emmer.templatesDir": "templates",
  "emmer.assetsDir": "assets",
  "emmer.autoBuild": true,
  "emmer.showDiagnostics": true
}
```

### Commands

The extension will now:
- Run builds from the correct root directory
- Watch files in the site directory
- Show errors for files in the site directory
- Validate templates in the site directory

## Benefits

1. **Separation of Concerns**: Site content is separate from Emmer code
2. **No Dependencies**: Site doesn't need `mix.exs` or Elixir dependencies
3. **Multiple Sites**: Can build multiple sites from one Emmer installation
4. **Clean Structure**: Site content is self-contained
5. **Easy Deployment**: Site directory can be deployed independently

## Example Workflow

1. **Setup**:
   ```bash
   # Create site directory
   mkdir my-website
   cd my-website

   # Initialize site structure
   mkdir content templates assets
   touch content/site.yaml
   ```

2. **Add Content**:
   ```html
   <!-- my-website/content/home/index.html -->
   {% layout "layout.html" %}
   <h1>{{ page.title }}</h1>
   <p>{{ page.description }}</p>
   ```

3. **Build from Emmer**:
   ```bash
   cd emmer
   ./bin/build ../my-website
   ```

4. **Watch for Changes**:
   ```bash
   cd emmer
   mix run -e 'SiteEmmer.watch([root_dir: "../my-website"])'
   ```

## CSS Generation

The build script will automatically:
1. Check for `package.json` in the root directory
2. Run `npm install` in the root directory
3. Run `npm run build:css:prod` in the root directory

This ensures CSS is generated in the correct location for the site.

## Deployment

The built site will be in `my-website/dist/` and can be deployed independently:

```bash
# Deploy just the site
rsync -avz my-website/dist/ user@server.com:/var/www/html/

# Or upload to CDN
aws s3 sync my-website/dist/ s3://my-bucket/
```

This approach makes Emmer much more flexible and suitable for real-world usage where you want to keep your site content separate from the build tools.
