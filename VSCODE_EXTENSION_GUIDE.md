# Emmer VS Code Extension - Complete Guide

## Overview

This guide explains how to create a VS Code extension that provides integrated error reporting for the Emmer static site generator. The extension shows build errors directly in the editor at the exact location where they occur, creating a seamless development experience.

## Architecture

### 1. Enhanced Emmer Core (`lib/site_emmer.ex`)

The Emmer core has been enhanced with structured error reporting:

```elixir
defmodule SiteEmmer.BuildError do
  @type t :: %__MODULE__{
    file: String.t(),
    line: non_neg_integer(),
    column: non_neg_integer(),
    message: String.t(),
    type: :template | :yaml | :build | :include,
    severity: :error | :warning
  }
end
```

**Key Enhancements:**
- `build_with_errors/1` - Returns structured errors instead of just building
- `build_page_with_errors/7` - Collects errors during page building
- `render_template_with_errors/4` - Captures template rendering errors
- `load_yaml_with_errors/1` - Handles YAML parsing errors
- Error conversion functions for Solid and YAML errors

### 2. VS Code Extension (`vscode-emmer/`)

The extension provides:
- **Real-time validation** of HTML templates and YAML files
- **Inline error reporting** with precise line/column locations
- **Integrated build commands** accessible via Command Palette
- **Problems panel integration** for comprehensive error viewing

## Key Components

### Extension Structure
```
vscode-emmer/
├── src/
│   ├── extension.ts      # Main extension logic
│   └── taskRunner.ts     # Build execution and error parsing
├── package.json          # Extension manifest
├── tsconfig.json         # TypeScript configuration
├── .vscode/
│   ├── launch.json       # Debug configuration
│   └── tasks.json        # Build tasks
├── examples/             # Example files with errors
└── README.md            # Documentation
```

### Core Classes

#### EmmerExtension
- Manages VS Code integration
- Handles commands and file watching
- Updates diagnostics collection
- Provides configuration management

#### EmmerTaskRunner
- Executes Emmer builds via `mix run`
- Parses structured error output
- Validates individual files
- Manages build processes

## Error Detection Capabilities

### Template Errors
1. **Unclosed Liquid tags**
   ```html
   {% if user.name %}
     Hello {{ user.name }}
   <!-- Missing endif - shows error -->
   ```

2. **Invalid variable syntax**
   ```html
   {{ invalid {{ nested }} braces }}
   <!-- Shows error for nested braces -->
   ```

3. **Missing includes/layouts**
   ```html
   {% include "missing-template.html" %}
   <!-- Shows error if template doesn't exist -->
   ```

### YAML Errors
1. **Tab characters**
   ```yaml
   page:
   	title: My Page  # Tab - shows error
   ```

2. **Inconsistent indentation**
   ```yaml
   page:
     title: My Page
   description: Wrong indentation  # Shows warning
   ```

### Build Errors
- File read/write failures
- Missing dependencies
- Configuration issues

## Usage Workflow

### 1. Development Setup
```bash
cd vscode-emmer
./install.sh
```

### 2. Extension Development
1. Open `vscode-emmer/` in VS Code
2. Press `F5` to launch extension in debug mode
3. Open an Emmer project in the new window
4. Edit files and see errors appear inline

### 3. User Experience
1. **Automatic Detection**: Extension detects Emmer projects automatically
2. **Real-time Validation**: Errors appear as you type
3. **Inline Indicators**: Red underlines show error locations
4. **Problems Panel**: Complete list of all errors
5. **Quick Fixes**: Commands to build, validate, and show errors

## Integration Points

### 1. Emmer Core Integration
The extension calls the enhanced Emmer build function:

```typescript
const args = [
  'run', '-e',
  `SiteEmmer.build_with_errors([
    source_dir: "${options.sourceDir || 'content'}",
    output_dir: "${options.outputDir || 'dist'}",
    templates_dir: "${options.templatesDir || 'templates'}",
    assets_dir: "${options.assetsDir || 'assets'}",
    verbose: ${options.verbose || false}
  ])`
];
```

### 2. Error Parsing
The extension parses structured error output:

```typescript
private parseErrorOutput(output: string, errors: EmmerError[]): void {
  const lines = output.split('\n');

  for (const line of lines) {
    const errorMatch = line.match(/^(.+?):(\d+):(\d+):\s*(.+)$/);
    if (errorMatch) {
      const [, file, lineStr, columnStr, message] = errorMatch;
      errors.push({
        file,
        line: parseInt(lineStr),
        column: parseInt(columnStr),
        message,
        type: 'template',
        severity: 'error'
      });
    }
  }
}
```

### 3. Diagnostics Integration
Errors are displayed using VS Code's diagnostics API:

```typescript
private updateDiagnostics(errors: EmmerError[]): void {
  const diagnosticsByFile = new Map<string, vscode.Diagnostic[]>();

  for (const error of errors) {
    const uri = vscode.Uri.file(error.file);
    const range = new vscode.Range(
      error.line - 1,
      error.column - 1,
      error.line - 1,
      error.column + 50
    );

    const diagnostic = new vscode.Diagnostic(
      range,
      error.message,
      error.severity === 'error' ? vscode.DiagnosticSeverity.Error : vscode.DiagnosticSeverity.Warning
    );

    diagnostic.source = 'Emmer';
    diagnostic.code = error.type;

    // Group by file
    const fileKey = uri.toString();
    if (!diagnosticsByFile.has(fileKey)) {
      diagnosticsByFile.set(fileKey, []);
    }
    diagnosticsByFile.get(fileKey)!.push(diagnostic);
  }

  // Set diagnostics for each file
  const entries: [vscode.Uri, vscode.Diagnostic[]][] = [];
  for (const [fileKey, diagnostics] of diagnosticsByFile) {
    entries.push([vscode.Uri.parse(fileKey), diagnostics]);
  }

  this.diagnosticCollection.set(entries);
}
```

## Configuration

### Extension Settings
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

### Commands Available
- `Emmer: Build Site` - Build the entire site
- `Emmer: Watch and Build` - Start watching for changes
- `Emmer: Validate Templates` - Validate all templates
- `Emmer: Show Build Errors` - Show errors panel

## Benefits

### 1. Developer Experience
- **Immediate Feedback**: Errors appear as you type
- **Precise Location**: Exact line and column for each error
- **Context**: Error messages explain what's wrong
- **Integration**: Works seamlessly with VS Code

### 2. Error Prevention
- **Template Validation**: Catches syntax errors early
- **YAML Validation**: Prevents formatting issues
- **Include Validation**: Ensures templates exist
- **Build Validation**: Catches runtime errors

### 3. Productivity
- **No Manual Checking**: Automatic validation
- **Quick Navigation**: Click errors to jump to location
- **Batch Operations**: Validate entire workspace
- **Real-time Updates**: Errors update as you save

## Example Error Output

When you have errors in your templates, they appear like this:

```
content/home/index.html:5:3: Unclosed if tag
content/home/index.html:12:1: Include template not found: missing-template.html
content/home/index.yaml:2:1: Tabs are not allowed in YAML, use spaces instead
```

These errors are:
1. **Parsed** by the extension
2. **Converted** to VS Code diagnostics
3. **Displayed** inline with red underlines
4. **Listed** in the Problems panel

## Future Enhancements

### 1. Quick Fixes
- Auto-fix for common YAML indentation issues
- Auto-close for Liquid tags
- Template creation for missing includes

### 2. Advanced Validation
- Variable existence checking
- Template dependency analysis
- Performance optimization suggestions

### 3. Integration Features
- Live preview generation
- Hot reload for development
- Git integration for error tracking

## Conclusion

This VS Code extension transforms Emmer development by providing:
- **Seamless error reporting** directly in the editor
- **Real-time validation** of templates and configuration
- **Integrated build tools** accessible via commands
- **Enhanced developer experience** with immediate feedback

The combination of enhanced Emmer core error reporting and VS Code extension integration creates a powerful, user-friendly development environment for static site generation.
