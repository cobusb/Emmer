# Emmer VS Code Extension

A comprehensive VS Code extension for the Emmer static site generator that provides integrated error reporting, real-time validation, and enhanced development experience.

## Features

### 🔍 Real-time Error Detection
- **Inline Error Reporting**: See build errors directly in your code with precise line and column locations
- **Template Validation**: Automatic validation of Liquid template syntax
- **YAML Validation**: Check for common YAML formatting issues
- **Include/Layout Validation**: Verify that referenced templates exist

### 🚀 Integrated Build Commands
- **Build Site**: Run `Emmer: Build Site` to build your static site
- **Watch Mode**: Run `Emmer: Watch and Build` for continuous building
- **Validate Templates**: Run `Emmer: Validate Templates` to check all files
- **Show Errors**: Run `Emmer: Show Build Errors` to view all detected issues

### ⚙️ Configuration
The extension can be configured through VS Code settings:

```json
{
  "emmer.sourceDir": "content",
  "emmer.outputDir": "dist",
  "emmer.templatesDir": "templates",
  "emmer.assetsDir": "assets",
  "emmer.autoBuild": false,
  "emmer.showDiagnostics": true
}
```

### 🎯 Error Types Detected

#### Template Errors
- Unclosed Liquid tags (`{% if %}`, `{% for %}`, etc.)
- Invalid variable syntax (nested `{{ }}`)
- Missing layout templates
- Missing include templates

#### YAML Errors
- Tab characters (not allowed in YAML)
- Inconsistent indentation
- Malformed YAML syntax

#### Build Errors
- File read/write failures
- Missing dependencies
- Configuration issues

## Installation

### Development Installation
1. Clone this repository
2. Run `npm install` to install dependencies
3. Run `npm run compile` to build the extension
4. Press `F5` in VS Code to launch the extension in debug mode

### Production Installation
1. Package the extension: `vsce package`
2. Install the `.vsix` file in VS Code

## Usage

### Basic Workflow
1. Open an Emmer project in VS Code
2. The extension automatically detects Emmer projects and starts validation
3. Edit your HTML templates and YAML files
4. Errors appear inline with red underlines
5. Use the Problems panel to see all errors at once

### Commands
- `Ctrl+Shift+P` → "Emmer: Build Site" - Build the entire site
- `Ctrl+Shift+P` → "Emmer: Watch and Build" - Start watching for changes
- `Ctrl+Shift+P` → "Emmer: Validate Templates" - Validate all templates
- `Ctrl+Shift+P` → "Emmer: Show Build Errors" - Show errors panel

### Error Indicators
- 🔴 **Red underline**: Error at that location
- 🟡 **Yellow underline**: Warning at that location
- 📋 **Problems panel**: Complete list of all errors

## Error Examples

### Template Error
```html
{% if user.name %}
  Hello {{ user.name }}
{% endif %}
<!-- Missing endif - will show error -->
```

### YAML Error
```yaml
page:
	title: My Page  # Tab character - will show error
  description: A page
```

### Include Error
```html
{% include "missing-template.html" %}
<!-- Template doesn't exist - will show error -->
```

## Integration with Emmer Core

This extension works with the enhanced Emmer core that provides structured error reporting:

```elixir
# In your Emmer project
SiteEmmer.build_with_errors([
  source_dir: "content",
  output_dir: "dist",
  templates_dir: "templates",
  verbose: true
])
```

The extension automatically calls this enhanced build function and parses the structured error output.

## Development

### Project Structure
```
vscode-emmer/
├── src/
│   ├── extension.ts      # Main extension logic
│   └── taskRunner.ts     # Build task execution
├── package.json          # Extension manifest
├── tsconfig.json         # TypeScript config
└── README.md            # This file
```

### Key Components

#### EmmerExtension
- Manages VS Code integration
- Handles commands and file watching
- Updates diagnostics collection

#### EmmerTaskRunner
- Executes Emmer builds
- Parses error output
- Validates individual files

### Adding New Error Types
1. Add error type to `EmmerError` interface
2. Implement validation logic in `validateHtmlFile()` or `validateYamlFile()`
3. Update error parsing in `parseErrorOutput()`

## Troubleshooting

### Extension Not Working
1. Check that you're in an Emmer project (has `mix.exs` with emmer dependency)
2. Verify Elixir and Mix are installed
3. Check the Output panel for error messages

### Build Errors Not Showing
1. Ensure `emmer.showDiagnostics` is enabled in settings
2. Check that files have correct extensions (`.html`, `.yaml`)
3. Verify file paths are correct

### Performance Issues
1. Disable `emmer.autoBuild` for large projects
2. Use file-specific validation instead of full workspace validation
3. Check that the Problems panel isn't overwhelming

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see LICENSE file for details.
