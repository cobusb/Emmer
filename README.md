# Emmer - Static Site Generator

[![Tests](https://github.com/cobusb/Emmer/actions/workflows/test.yml/badge.svg)](https://github.com/cobusb/Emmer/actions)
[![Coverage](https://coveralls.io/repos/github/cobusb/Emmer/badge.svg?branch=main)](https://coveralls.io/github/cobusb/Emmer?branch=main)

A static site generator built in Elixir that crawls folders for HTML and YAML files, matches them up, and generates content using Solid templating.

## Features

- **Folder-based content organization**: Each page/section gets its own folder
- **YAML data files**: Separate data from presentation
- **Layout system**: Use layouts with `{% layout "layout.html" %}`
- **Include system**: Include reusable components with `{% include "header.html" %}`
- **Solid templating**: Liquid-compatible templating engine
- **GitHub Actions integration**: Automatic builds with flexible deployment options
- **Local development**: Build and test locally

## Sample Project Structure

```
your-site/
├── content/                    # Source content
│   ├── site.yaml              # Global site data
│   ├── home/
│   │   ├── index.html         # Home page content
│   │   └── index.yaml         # Home page data
│   ├── eredienste/
│   │   ├── index.html         # Services page content
│   │   └── index.yaml         # Services page data
│   └── contact/
│       ├── index.html         # Contact page content
│       └── index.yaml         # Contact page data
├── templates/                  # Reusable templates
│   ├── layout.html            # Main layout template
│   ├── header.html            # Header component
│   └── footer.html            # Footer component
├── css/                       # Static assets
├── js/
├── images/
└── dist/                      # Generated site (output)
```

## Installation

1. Clone this repository
2. Install Elixir dependencies:
   ```bash
   mix deps.get
   ```
3. Install Node.js dependencies (for CSS generation):
   ```bash
   npm install
   ```

## Usage

### Local Development

Build the site locally:

```bash
# Using the CLI script (includes CSS generation)
./bin/build

# Or using Elixir directly
elixir -e "SiteEmmer.build()"

# With custom directories
./bin/build --source-dir content --output-dir dist --templates-dir templates

# Build CSS only
npm run build:css:prod

# Build CSS in watch mode (development)
npm run build:css
```

### GitHub Actions Build

The site will automatically build when you push to the `main` branch. The built site is available as a downloadable artifact.

### Deployment Options

The build process creates a `dist/` directory with your static site. You can deploy this to any web server:

#### GitHub Pages
Add this step to your workflow:
```yaml
- name: Deploy to GitHub Pages
  if: github.ref == 'refs/heads/main'
  uses: peaceiris/actions-gh-pages@v3
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./dist
```

#### Custom Server (rsync)
Add this step to your workflow:
```yaml
- name: Deploy to server
  if: github.ref == 'refs/heads/main'
  run: |
    rsync -avz --delete dist/ user@your-server.com:/var/www/html/
```

#### Custom Server (scp)
Add this step to your workflow:
```yaml
- name: Deploy to server
  if: github.ref == 'refs/heads/main'
  run: |
    scp -r dist/* user@your-server.com:/var/www/html/
```

#### Netlify/Vercel
Connect your repository to Netlify or Vercel and set the build directory to `dist/`.

## Content Format

### HTML Content Files

Content files can use layouts and includes:

```html
{% layout "layout.html" %}

<h1 class="text-4xl font-bold text-center mb-8">
    Welkom by {{ site.name }}
</h1>

<div class="grid md:grid-cols-2 gap-8">
    <div>
        <h2 class="text-2xl font-semibold mb-4">Ons Eredienste</h2>
        <p>Sondag: 10:00</p>
        <p>Woensdag: 19:00</p>
    </div>

    <div>
        <h2 class="text-2xl font-semibold mb-4">Kontak</h2>
        <p>{{ site.contact.address }}</p>
        <p>Tel: {{ site.contact.phone }}</p>
        <p>Email: {{ site.contact.email }}</p>
    </div>
</div>

{% if sermons %}
<h2 class="text-2xl font-semibold mt-8 mb-4">Laaste Preek</h2>
<div class="bg-gray-100 p-4 rounded">
    <h3 class="font-semibold">{{ sermons[0].title }}</h3>
    <p class="text-gray-600">{{ sermons[0].date }} - {{ sermons[0].preacher }}</p>
    <p class="text-sm">{{ sermons[0].scripture }}</p>
</div>
{% endif %}
```

### Layout Templates

Layout templates define the overall page structure:

```html
<!DOCTYPE html>
<html lang="af">
<head>
    <meta charset="UTF-8">
    <title>{{ page.title }} - {{ site.name }}</title>
    <link href="/css/tailwind.css" rel="stylesheet">
</head>
<body>
    {% include "header.html" %}

    <main class="container mx-auto px-4">
        {{ content }}
    </main>

    {% include "footer.html" %}
</body>
</html>
```

### YAML Data Files

#### Global Site Data (`content/site.yaml`)

```yaml
site:
  name: "Vrye Gereformeerde Kerk Johannesburg"
  description: "Ons is 'n gemeenskap van Christene wat die Here aanbid"
  contact:
    address: "14 Cornelis Straat, Johannesburg"
    phone: "+27 83 326 4597"
    email: "skriba@vgkjhb.org.za"
    maps_url: "https://maps.app.goo.gl/fojbDGZYkNQLaWsU6"
```

#### Page-Specific Data (`content/home/index.yaml`)

```yaml
page:
  title: "Tuis"
  description: "Welkom by ons gemeente"
sermons:
  - title: "Die Genade van God"
    date: "2024-01-14"
    preacher: "Ds. Smith"
    scripture: "Efesiërs 2:8-9"
```

## Template Features

### Layouts

Use `{% layout "layout.html" %}` at the top of your content files to apply a layout template.

### Includes

Use `{% include "component.html" %}` to include reusable components.

### Variables

Access data using Liquid syntax:
- `{{ site.name }}` - Global site data
- `{{ page.title }}` - Page-specific data
- `{{ content }}` - The rendered content (in layouts)

### Conditionals

```liquid
{% if sermons %}
  <!-- Show sermons -->
{% endif %}
```

### Loops

```liquid
{% for sermon in sermons %}
  <div class="sermon">
    <h3>{{ sermon.title }}</h3>
    <p>{{ sermon.date }}</p>
  </div>
{% endfor %}
```

## Configuration

### Custom Directories

You can specify custom directories when building:

```bash
./bin/build --source-dir my-content --output-dir my-dist --templates-dir my-templates
```

### GitHub Pages

To enable GitHub Pages, add the deployment step to your workflow as shown in the deployment options above, then:

1. Go to your repository settings
2. Navigate to "Pages"
3. Set source to "GitHub Actions"

## Development

### Adding New Pages

1. Create a new folder in `content/`
2. Add `index.html` with your content
3. Add `index.yaml` with page-specific data
4. Build the site

### Adding New Templates

1. Add HTML files to the `templates/` directory
2. Reference them in your content files using `{% include "template.html" %}`

### GitHub Actions Workflow

To enable automatic builds on GitHub, create `.github/workflows/build.yml`:

```yaml
name: Build Static Site

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.18.4'
        otp-version: '26.0'

    - name: Install dependencies
      run: |
        mix local.hex --force
        mix local.rebar --force
        mix deps.get

    - name: Build site
      run: |
        elixir -e "SiteEmmer.build()"

    - name: Upload build artifacts
      uses: actions/upload-artifact@v4
      with:
        name: site-build
        path: dist/
        retention-days: 30
```

This workflow will:
- Build your site on every push to main
- Make the built site available as a downloadable artifact
- Allow you to add custom deployment steps as needed

## License

MIT License
# Test commit
