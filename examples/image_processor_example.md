# Image Processor Example

This example demonstrates how to use the `Emmer.Processor.Image` processor with the Image library (hex package: image) to process images dynamically through YAML configuration.

## Overview

The Image processor allows you to:
- Execute any Image library function through YAML configuration
- Chain multiple operations in a pipeline
- Handle complex arguments including keyword lists
- Process images with resize, crop, thumbnail, and other operations
- Apply filters, transformations, and format conversions
- Direct specification of output paths in operations
- Dynamic data injection for text overlays and watermarks using `__DATA.key__` placeholders

## Prerequisites

Add the image dependency to your `mix.exs`:

```elixir
defp deps do
  [
    {:image, "~> 0.38"},
    # ... other dependencies
  ]
end
```

## Basic Setup

### Project Structure
```
my-site/
├── emmer.config.yaml
├── content/
│   ├── folder.yaml
│   └── photos/
│       ├── folder.yaml
│       ├── profile.jpg
│       ├── hero.png
│       └── gallery/
│           ├── photo1.jpg
│           └── photo2.jpg
└── dist/  # Output directory
```

## Configuration Examples

### 1. Simple Resize

Resize all images to a fixed size:

```yaml
config:
  processors:
    - name: "resize_photos"
      module: "Emmer.Processor.Image"
      filter:
        regex: "\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        - module: "Image"
          function: "resize"
          args: [800, 600]
        - module: "Image"
          function: "write!"
          args: ["dist/images/resized/photo.jpg"]
```

### 2. Create Thumbnails

Generate thumbnails with center cropping:

```yaml
config:
  processors:
    - name: "create_thumbnails"
      module: "Emmer.Processor.Image"
      filter:
        regex: "\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        - module: "Image"
          function: "thumbnail"
          args: [
            300,
            300,
            [
              opts: {
                crop: ":center"
              }
            ]
          ]
        - module: "Image"
          function: "write!"
          args: ["dist/images/thumbs/thumbnail.jpg"]
```

### 3. Convert Format with Quality Settings

Convert images to JPEG with specific quality:

```yaml
config:
  processors:
    - name: "convert_to_jpeg"
      module: "Emmer.Processor.Image"
      filter:
        regex: "\\.(png|gif)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        - module: "Image"
          function: "write"
          args: [
            "dist/images/converted/image.jpg",
            ":jpeg",
            [
              opts: {
                quality: 85,
                progressive: true
              }
            ]
          ]
```

### 4. Complex Pipeline with Multiple Operations

Apply multiple transformations in sequence:

```yaml
config:
  processors:
    - name: "process_hero_images"
      module: "Emmer.Processor.Image"
      filter:
        regex: "hero.*\\.(jpg|png)$"
      operations:
        # Open the image
        - module: "Image"
          function: "open!"
          args: []
        
        # Resize to max width/height while maintaining aspect ratio
        - module: "Image"
          function: "resize_to_limit"
          args: [1920, 1080]
        
        # Apply blur effect
        - module: "Image"
          function: "blur"
          args: [2.5]
        
        # Adjust brightness
        - module: "Image"
          function: "brightness"
          args: [1.1]
        
        # Write with compression
        - module: "Image"
          function: "write!"
          args: [
            "dist/images/hero/hero.webp",
            [
              opts: {
                quality: 90,
                suffix: ".webp"
              }
            ]
          ]
```

### 5. Watermark Images

Add watermarks to images:

```yaml
config:
  processors:
    - name: "add_watermark"
      module: "Emmer.Processor.Image"
      filter:
        regex: "\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        
        # Note: This assumes you have a watermark function or use compose
        - module: "Image"
          function: "compose"
          args: [
            "path/to/watermark.png",
            [
              opts: {
                x: 10,
                y: 10,
                blend_mode: ":over"
              }
            ]
          ]
        
        - module: "Image"
          function: "write!"
          args: ["dist/images/watermarked/watermarked.jpg"]
```

### 6. Responsive Image Generation

Generate multiple sizes for responsive design:

```yaml
config:
  processors:
    # Small size
    - name: "responsive_small"
      module: "Emmer.Processor.Image"
      filter:
        regex: "\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        - module: "Image"
          function: "resize_to_limit"
          args: [640, 480]
        - module: "Image"
          function: "write!"
          args: ["dist/images/small/small.jpg"]
    
    # Medium size
    - name: "responsive_medium"
      module: "Emmer.Processor.Image"
      filter:
        regex: "\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        - module: "Image"
          function: "resize_to_limit"
          args: [1024, 768]
        - module: "Image"
          function: "write!"
          args: ["dist/images/medium/medium.jpg"]
    
    # Large size
    - name: "responsive_large"
      module: "Emmer.Processor.Image"
      filter:
        regex: "\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        - module: "Image"
          function: "resize_to_limit"
          args: [1920, 1080]
        - module: "Image"
          function: "write!"
          args: ["dist/images/large/large.jpg"]
```

## Configuration Options

### Processor Configuration

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `operations` | Yes | - | List of operations to perform |
| `filter` | No | - | Standard Emmer filter to select files |

### Operation Configuration

Each operation in the `operations` list must have:

| Field | Required | Description |
|-------|----------|-------------|
| `module` | Yes | The Image module to use (e.g., "Image", "Image.Thumbnail") |
| `function` | Yes | The function to call (e.g., "resize", "open!") |
| `args` | No | Arguments to pass to the function (array) |

### Argument Types

The processor supports various argument types:

1. **Simple values**: Strings, numbers, booleans
   ```yaml
   args: [800, 600, true]
   ```

2. **Atoms**: Strings starting with ":"
   ```yaml
   args: [":jpeg", ":center"]
   ```

3. **Keyword lists**: Using `opts` key
   ```yaml
   args: [
     300,
     [
       opts: {
         crop: ":center",
         quality: 85
       }
     ]
   ]
   ```

4. **Special placeholders**:
   - `__OUTPUT_PATH__`: Replaced with the actual output path
   - `__DATA.key__`: Replaced with data values from the YAML configuration (e.g., `__DATA.site_name__`)

## Common Image Operations

### Opening and Writing

```yaml
operations:
  - module: "Image"
    function: "open!"
    args: []
  # ... other operations ...
  - module: "Image"
    function: "write!"
    args: ["dist/output/image.jpg"]
```

### Resizing

```yaml
# Fixed size
- module: "Image"
  function: "resize"
  args: [800, 600]

# Maintain aspect ratio
- module: "Image"
  function: "resize_to_limit"
  args: [1920, 1080]
```

### Cropping

```yaml
- module: "Image"
  function: "crop"
  args: [0, 0, 500, 500]
```

### Format Conversion

```yaml
- module: "Image"
  function: "write"
  args: [
    "dist/images/output.webp",
    ":webp",
    [
      opts: {
        quality: 80
      }
    ]
  ]
```

## Error Handling

The processor provides detailed error messages for:

### Missing Configuration
```
[error] Image configuration error: Missing required 'operations' configuration
```

### Module Loading Errors
```
[error] Image: Error executing Image.InvalidFunction: Function Image.InvalidFunction/2 not found
```

### Processing Errors
```
[error] Image: Failed to process photo.jpg: Error executing Image.resize: invalid dimensions
```

## Best Practices

1. **Always start with `open!`** - Load the image before processing
2. **End with `write!` or `write`** - Save the processed image
3. **Use `resize_to_limit`** for responsive images to maintain aspect ratio
4. **Chain operations** efficiently - each operation's output becomes the next's input
5. **Test operations** with a small set of images first
6. **Use appropriate formats** - JPEG for photos, PNG for graphics with transparency
7. **Set quality appropriately** - 85-90 for high quality, 70-80 for web optimization

## Tips

1. **Performance**: Process images during build time to avoid runtime overhead
2. **Batch processing**: Use filters to process specific image types differently
3. **Error recovery**: The processor continues with other images if one fails
4. **Debugging**: Check logs for detailed operation execution information
5. **Module discovery**: Refer to Image library documentation for available functions

## Advanced Example: Art Gallery Processing

```yaml
config:
  processors:
    # High-quality gallery images
    - name: "gallery_full"
      module: "Emmer.Processor.Image"
      filter:
        regex: "gallery/.*\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        - module: "Image"
          function: "resize_to_limit"
          args: [2400, 1600]
        - module: "Image"
          function: "write"
          args: [
            "dist/gallery/full/image.jpg",
            ":jpeg",
            [
              opts: {
                quality: 95,
                progressive: true
              }
            ]
          ]
    
    # Gallery thumbnails
    - name: "gallery_thumbs"
      module: "Emmer.Processor.Image"
      filter:
        regex: "gallery/.*\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        - module: "Image"
          function: "thumbnail"
          args: [
            400,
            300,
            [
              opts: {
                crop: ":attention"
              }
            ]
          ]
        - module: "Image"
          function: "write!"
          args: ["dist/gallery/thumbs/thumb.jpg"]
```

### 7. Dynamic Text Overlays with Data

Generate branded images using data from your YAML configuration:

```yaml
data:
  site_name: "My Company"
  contact_email: "info@mycompany.com"
  branding:
    font_size: 32
    color: "white"
    logo_text: "© My Company 2024"

config:
  processors:
    - name: "brand_images"
      module: "Emmer.Processor.Image"
      filter:
        regex: "(hero|banner).*\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
        
        # Add company name at top
        - module: "Image"
          function: "text!"
          args: [
            "__DATA.site_name__",
            [
              opts: {
                x: 50,
                y: 50,
                font_size: "__DATA.branding.font_size__",
                color: "__DATA.branding.color__",
                font: "Arial-Bold"
              }
            ]
          ]
        
        # Add contact info at bottom
        - module: "Image"
          function: "text!"
          args: [
            "__DATA.contact_email__",
            [
              opts: {
                x: 50,
                y: -100,  # Negative means from bottom
                font_size: 18,
                color: "rgba(255,255,255,0.8)"
              }
            ]
          ]
        
        # Add copyright notice
        - module: "Image"
          function: "text!"
          args: [
            "__DATA.branding.logo_text__",
            [
              opts: {
                x: -20,   # Negative means from right
                y: -20,   # Bottom right corner
                font_size: 14,
                color: "rgba(255,255,255,0.6)",
                align: "right"
              }
            ]
          ]
        
        - module: "Image"
          function: "write!"
          args: ["dist/images/branded/branded-image.jpg"]
```

### 8. Conditional Processing with Data

You can also use data values in conditions and operations:

```yaml
data:
  watermark:
    enabled: true
    text: "CONFIDENTIAL"
    opacity: 0.5
    
config:
  processors:
    - name: "conditional_watermark"
      module: "Emmer.Processor.Image"
      filter:
        regex: "documents/.*\\.(jpg|png)$"
      operations:
        - module: "Image"
          function: "open!"
          args: []
          
        # Only add watermark if enabled in data
        - module: "Image"
          function: "text!"
          args: [
            "__DATA.watermark.text__",
            [
              opts: {
                x: "center",
                y: "center",
                font_size: 48,
                color: "rgba(255,0,0,__DATA.watermark.opacity__)",
                angle: 45,
                font: "Arial-Bold"
              }
            ]
          ]
        
        - module: "Image"
          function: "write!"
          args: ["dist/images/watermarked/document.jpg"]
```

## Data Placeholder Format

Data placeholders use the format `__DATA.key__` where `key` can be:

- Simple keys: `__DATA.site_name__`
- Nested keys: `__DATA.branding.color__` 
- Deep nesting: `__DATA.config.theme.primary_color__`

If a data key is not found, the placeholder string is used as-is (falls back gracefully).

This processor provides a flexible way to integrate the powerful Image library into your Emmer build pipeline, allowing for sophisticated image processing workflows configured entirely through YAML with dynamic data injection.