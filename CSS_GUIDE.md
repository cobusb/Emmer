# 🎨 CSS Generation Guide for Emmer

This guide explains how to generate optimized CSS for your Emmer static site using Tailwind CSS.

## 📋 Overview

Emmer integrates with Tailwind CSS to automatically generate optimized CSS based on the classes used in your HTML templates and content files.

## 🚀 Quick Start

### 1. Install Dependencies

```bash
# Install Node.js dependencies
npm install

# Or install globally
npm install -g tailwindcss @tailwindcss/typography @tailwindcss/forms
```

### 2. Build CSS

```bash
# Build CSS for production (minified)
npm run build:css:prod

# Build CSS for development (with watch mode)
npm run build:css
```

### 3. Build Site with CSS

```bash
# Build site with automatic CSS generation
./bin/build
```

## 🛠️ Manual CSS Generation

### Using the Elixir Script

```bash
# Generate CSS from HTML files
elixir scripts/build-css.exs
```

### Using Tailwind CLI Directly

```bash
# Build CSS from input file
npx tailwindcss --input ./assets/css/input.css --output ./assets/css/tailwind.css --minify

# Watch mode for development
npx tailwindcss --input ./assets/css/input.css --output ./assets/css/tailwind.css --watch
```

## 📁 File Structure

```
your-site/
├── assets/
│   └── css/
│       ├── input.css          # Tailwind directives and custom styles
│       └── tailwind.css       # Generated CSS (output)
├── content/                   # HTML content files
├── templates/                 # HTML template files
├── tailwind.config.js        # Tailwind configuration
├── package.json              # Node.js dependencies
└── scripts/
    └── build-css.exs         # CSS generation script
```

## ⚙️ Configuration

### Tailwind Config (`tailwind.config.js`)

```javascript
module.exports = {
  content: [
    "./content/**/*.html",    // Scan content files
    "./templates/**/*.html",  // Scan template files
    "./assets/**/*.js"        // Scan JavaScript files
  ],
  theme: {
    extend: {
      colors: {
        primary: { /* Your brand colors */ },
        secondary: { /* Secondary colors */ }
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        serif: ['Georgia', 'serif'],
      }
    },
  },
  plugins: [
    require('@tailwindcss/typography'),
    require('@tailwindcss/forms'),
  ],
}
```

### Input CSS (`assets/css/input.css`)

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

/* Custom base styles */
@layer base {
  body {
    @apply text-gray-900 bg-white;
  }
}

/* Custom component styles */
@layer components {
  .btn {
    @apply inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md;
  }
}

/* Custom utility styles */
@layer utilities {
  .text-shadow {
    text-shadow: 0 2px 4px rgba(0,0,0,0.1);
  }
}
```

## 🎯 How It Works

### 1. Content Scanning

The build process scans all HTML files in:
- `content/` directory (your page content)
- `templates/` directory (your layout templates)

### 2. Class Extraction

Tailwind analyzes the HTML files and extracts all used classes:
- `class="text-blue-500 bg-white"` → extracts `text-blue-500`, `bg-white`
- `class="container mx-auto px-4"` → extracts `container`, `mx-auto`, `px-4`

### 3. CSS Generation

Only the CSS for used classes is generated:
- **Unused classes**: Excluded from final CSS
- **Used classes**: Included with all variants (hover, focus, etc.)
- **Custom classes**: Included based on your configuration

### 4. Optimization

The generated CSS is:
- **Purged**: Only includes used styles
- **Minified**: Compressed for production
- **Optimized**: Efficient and fast-loading

## 📊 Performance Benefits

### Before Optimization
```css
/* Full Tailwind CSS (unoptimized) */
.text-blue-500 { color: #3b82f6; }
.text-blue-600 { color: #2563eb; }
.text-blue-700 { color: #1d4ed8; }
/* ... thousands more unused classes */
```

### After Optimization
```css
/* Optimized CSS (only used classes) */
.text-blue-500 { color: #3b82f6; }
.bg-white { background-color: #ffffff; }
.container { max-width: 100%; }
/* ... only the classes you actually use */
```

## 🎨 Customization

### Adding Custom Colors

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#f0f9ff',
          500: '#3b82f6',
          900: '#1e3a8a',
        }
      }
    }
  }
}
```

### Adding Custom Components

```css
/* assets/css/input.css */
@layer components {
  .card {
    @apply bg-white rounded-lg shadow-md border border-gray-200 overflow-hidden;
  }

  .btn-primary {
    @apply bg-blue-600 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded;
  }
}
```

### Adding Custom Utilities

```css
/* assets/css/input.css */
@layer utilities {
  .text-shadow {
    text-shadow: 0 2px 4px rgba(0,0,0,0.1);
  }

  .backdrop-blur {
    backdrop-filter: blur(10px);
  }
}
```

## 🔧 Development Workflow

### 1. Development Mode

```bash
# Start CSS watcher
npm run build:css

# In another terminal, build site
./bin/build
```

### 2. Production Build

```bash
# Build optimized CSS
npm run build:css:prod

# Build site
./bin/build
```

### 3. GitHub Actions Integration

The CSS build is automatically included in the build process:

```yaml
# .github/workflows/build.yml
- name: Build CSS
  run: npm install && npm run build:css:prod

- name: Build Site
  run: ./bin/build
```

## 🚨 Troubleshooting

### Common Issues

**CSS not updating:**
```bash
# Clear cache and rebuild
rm -rf node_modules package-lock.json
npm install
npm run build:css:prod
```

**Classes not being detected:**
```bash
# Check if files are in content paths
ls content/**/*.html
ls templates/**/*.html
```

**Build errors:**
```bash
# Check Node.js version
node --version

# Check npm version
npm --version

# Reinstall dependencies
npm ci
```

### Debug Commands

```bash
# Check what classes are being extracted
elixir scripts/build-css.exs

# Check Tailwind config
npx tailwindcss --help

# Build with verbose output
npx tailwindcss --input ./assets/css/input.css --output ./assets/css/tailwind.css --verbose
```

## 📚 Best Practices

### 1. Use Semantic Class Names

```html
<!-- Good -->
<div class="card">
  <h2 class="text-2xl font-bold text-gray-900">Title</h2>
</div>

<!-- Avoid -->
<div class="bg-white rounded-lg shadow-md p-6">
  <h2 class="text-2xl font-bold text-gray-900">Title</h2>
</div>
```

### 2. Organize Custom Styles

```css
/* assets/css/input.css */
@layer components {
  /* Layout components */
  .container { @apply max-w-7xl mx-auto px-4; }
  .section { @apply py-12 md:py-16; }

  /* UI components */
  .btn { @apply px-4 py-2 rounded font-medium; }
  .card { @apply bg-white rounded-lg shadow-md; }

  /* Typography */
  .heading { @apply text-3xl font-bold text-gray-900; }
  .subtitle { @apply text-lg text-gray-600; }
}
```

### 3. Use CSS Variables for Theming

```css
/* assets/css/input.css */
:root {
  --primary-color: #3b82f6;
  --secondary-color: #64748b;
}

@layer components {
  .btn-primary {
    @apply bg-blue-600 hover:bg-blue-700;
    background-color: var(--primary-color);
  }
}
```

## 🎯 Advanced Features

### Dark Mode Support

```javascript
// tailwind.config.js
module.exports = {
  darkMode: 'class', // or 'media'
  // ... rest of config
}
```

```html
<!-- In your templates -->
<html class="dark">
  <body class="bg-white dark:bg-gray-900 text-gray-900 dark:text-white">
    <!-- Content -->
  </body>
</html>
```

### Responsive Design

```html
<!-- Mobile-first responsive design -->
<div class="w-full md:w-1/2 lg:w-1/3">
  <h2 class="text-lg md:text-xl lg:text-2xl">Title</h2>
</div>
```

### Animation Support

```css
/* assets/css/input.css */
@layer utilities {
  .animate-fade-in {
    animation: fadeIn 0.5s ease-in-out;
  }
}

@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}
```

This setup gives you a powerful, optimized CSS generation system that automatically includes only the styles you actually use in your static site!
