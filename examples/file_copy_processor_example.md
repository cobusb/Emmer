# FileCopy Processor Example

This example demonstrates how to use the `Emmer.Processor.FileCopy` processor to copy files to specified output directories.

## Overview

The FileCopy processor is useful for:
- Copying static assets (images, PDFs, etc.) to output directories
- Creating backups of files during the build process
- Moving files to different locations while preserving or flattening directory structure

## Basic Setup

### Project Structure
```
my-site/
├── emmer.config.yaml
├── content/
│   ├── folder.yaml
│   ├── images/
│   │   ├── folder.yaml
│   │   ├── logo.png
│   │   └── hero.jpg
│   └── documents/
│       ├── folder.yaml
│       ├── manual.pdf
│       └── guide.pdf
└── dist/  # Output directory
```

### Configuration Files

#### emmer.config.yaml
```yaml
builder:
  verbose_logging: "debug"
  source_folder: "content"

context:
  site_name: "My Website"
  output_dir: "dist"
```

#### content/folder.yaml
```yaml
config:
  processors: []

data:
  title: "Main Content"
```

#### content/images/folder.yaml
```yaml
config:
  processors:
    - name: "copy_images"
      module: "Emmer.Processor.FileCopy"
      output_dir: "dist/assets/images"
      filter:
        regex: "\\.(png|jpg|jpeg|gif|svg)$"

data:
  section: "images"
```

#### content/documents/folder.yaml
```yaml
config:
  processors:
    - name: "copy_docs"
      module: "Emmer.Processor.FileCopy"
      output_dir: "dist/downloads"
      preserve_structure: false
      filter:
        regex: "\\.(pdf|doc|docx)$"

data:
  section: "documents"
```

## Advanced Examples

### 1. Preserve Directory Structure

When you want to maintain the original folder hierarchy:

```yaml
config:
  processors:
    - name: "copy_all_assets"
      module: "Emmer.Processor.FileCopy"
      output_dir: "dist/static"
      preserve_structure: true
      filter:
        regex: "\\.(png|jpg|css|js|pdf)$"
```

**Result:**
- `content/images/logo.png` → `dist/static/images/logo.png`
- `content/docs/manual.pdf` → `dist/static/docs/manual.pdf`

### 2. Flatten Directory Structure

When you want all files in a single output directory:

```yaml
config:
  processors:
    - name: "flatten_images"
      module: "Emmer.Processor.FileCopy"
      output_dir: "dist/all-images"
      preserve_structure: false
      filter:
        regex: "\\.(png|jpg|jpeg)$"
```

**Result:**
- `content/images/logo.png` → `dist/all-images/logo.png`
- `content/gallery/photo.jpg` → `dist/all-images/photo.jpg`

### 3. Multiple Copy Operations

You can have multiple FileCopy processors in the same folder:

```yaml
config:
  processors:
    # Copy images to assets folder
    - name: "copy_images"
      module: "Emmer.Processor.FileCopy"
      output_dir: "dist/assets"
      filter:
        regex: "\\.(png|jpg|jpeg|gif|svg)$"
    
    # Also backup images to separate location
    - name: "backup_images"
      module: "Emmer.Processor.FileCopy"
      output_dir: "../backups/images"
      preserve_structure: true
      filter:
        regex: "\\.(png|jpg|jpeg|gif|svg)$"
```

### 4. Conditional Processing with Filters

Copy only specific file types or names:

```yaml
config:
  processors:
    # Only copy large images
    - name: "copy_hero_images"
      module: "Emmer.Processor.FileCopy"
      output_dir: "dist/hero-images"
      filter:
        regex: "(hero|banner|background)\\.(png|jpg)$"
    
    # Copy all PDFs except drafts
    - name: "copy_final_docs"
      module: "Emmer.Processor.FileCopy"
      output_dir: "dist/documents"
      filter:
        regex: "^(?!.*draft).*\\.pdf$"
```

## Expected Build Output

When you run the build, you'll see logs like:

```
[info] build_123 FileCopy: Copied logo.png to dist/assets/images/logo.png
[info] build_123 FileCopy: Copied hero.jpg to dist/assets/images/hero.jpg
[info] build_123 FileCopy: Copied manual.pdf to dist/downloads/manual.pdf
[debug] build_123 FileCopy: Processing content/images/logo.png
[debug] build_123 FileCopy: content/images/logo.png -> dist/assets/images/logo.png
```

## Common Use Cases

### Static Site Assets
```yaml
processors:
  - name: "copy_static_assets"
    module: "Emmer.Processor.FileCopy"
    output_dir: "dist/static"
    preserve_structure: true
    filter:
      regex: "\\.(css|js|png|jpg|svg|ico|woff|woff2)$"
```

### Document Publishing
```yaml  
processors:
  - name: "publish_docs"
    module: "Emmer.Processor.FileCopy"
    output_dir: "../published-docs"
    filter:
      regex: "\\.(pdf|docx|pptx)$"
```

### Media Processing
```yaml
processors:
  - name: "copy_media"
    module: "Emmer.Processor.FileCopy"
    output_dir: "dist/media"
    preserve_structure: false
    filter:
      regex: "\\.(mp4|mp3|avi|mov|wav)$"
```

## Configuration Options

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `output_dir` | Yes | - | Directory to copy files to (relative to project root or absolute) |
| `preserve_structure` | No | `false` | Whether to maintain original directory structure |
| `filter` | No | - | Standard Emmer filter (regex, etc.) to select files |

## Output Directory Behavior

The `output_dir` is resolved relative to the **project root** (where `emmer.config.yaml` is located), not relative to the current folder being processed.

### Examples:

**Project Structure:**
```
my-project/
├── emmer.config.yaml          # ← Project root
├── content/
│   └── images/
│       ├── folder.yaml
│       └── logo.png
└── dist/                      # ← Output directory created here
```

**Configuration in `content/images/folder.yaml`:**
```yaml
config:
  processors:
    - name: "copy_images"
      module: "Emmer.Processor.FileCopy"
      output_dir: "dist/images"  # Relative to project root
```

**Result:**
- Files are copied to: `my-project/dist/images/`
- NOT to: `my-project/content/images/dist/images/`

### Path Resolution:

| `output_dir` Value | Resolves To |
|-------------------|-------------|
| `"dist/images"` | `{project_root}/dist/images/` |
| `"../output"` | `{project_root}/../output/` |
| `"/tmp/backup"` | `/tmp/backup/` (absolute, unchanged) |

## Error Handling

The processor will log errors for:
- Missing or invalid `output_dir` configuration
- File system errors (permissions, disk space, etc.)
- Source files that don't exist or can't be read

Example error logs:
```
[error] build_123 FileCopy configuration error: Missing required 'output_dir' configuration
[error] build_123 FileCopy: Failed to copy image.png to dist/images/image.png: eacces
```

## Tips

1. **Use relative paths** for `output_dir` when possible for portability - they resolve relative to the project root
2. **Remember path resolution** - `output_dir` is always relative to where `emmer.config.yaml` is located
3. **Combine with filters** to avoid copying unwanted files (e.g., exclude `.webp` if you only want `.jpg`, `.png`, `.gif`)
4. **Set `preserve_structure: true`** when you need to maintain folder hierarchy in the output
5. **Test with different file types** to ensure your regex filters work correctly
6. **Check file permissions** if you encounter copy errors
7. **Use absolute paths** only when you need to copy files outside the project structure