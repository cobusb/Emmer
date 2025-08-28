# Emmer Cloud

A cloud-based preview proxy for local Emmer static site generators. Share your work-in-progress sites with clients and team members without exposing your local development environment.

## Features

- 🌐 **Cloud-based previews** - Access your local sites from anywhere
- 🔄 **Real-time updates** - Changes in your local files are reflected immediately
- 🔗 **Automatic link rewriting** - All internal links work correctly in the cloud
- 📦 **Asset proxying** - CSS, JS, images, and other assets are served through the cloud
- 🏷️ **Unique subdomains** - Each local server gets its own subdomain
- 💓 **Heartbeat monitoring** - Automatic health checks and cleanup
- 🔒 **Secure** - No need to expose your local development server

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Local Emmer   │    │   Emmer Cloud    │    │   Client/Team   │
│     Server      │◄──►│      Proxy       │◄──►│    Member       │
│                 │    │                  │    │                 │
│ - Watches files │    │ - Registers      │    │ - Views preview │
│ - Builds sites  │    │   local servers  │    │ - Shares URL    │
│ - Serves files  │    │ - Proxies        │    │                 │
└─────────────────┘    │   requests       │    └─────────────────┘
                       │ - Rewrites links │
                       └──────────────────┘
```

## Quick Start

### 1. Start the Cloud Proxy

```bash
cd emmer_cloud
mix deps.get
mix ecto.create
mix phx.server
```

The cloud proxy will be available at `http://localhost:4000`

### 2. Register Your Local Server

In your local Emmer project, register with the cloud:

```elixir
# In your local Emmer project
mix run -e "
EmmerCloud.Client.register_with_cloud(
  \"My Awesome Site\",
  \"http://localhost:4116\",
  \"http://localhost:4000\"
)
"
```

### 3. Share the Preview URL

The registration will return a cloud URL like:
```
https://server_1.emmer.cloud
```

Share this URL with your team or clients!

## API Reference

### Registration

```elixir
# Register a local server
EmmerCloud.Client.register_with_cloud(name, local_url, cloud_url)

# Returns:
{:ok, %{
  "success" => true,
  "server_id" => "server_1",
  "subdomain" => "server_1",
  "cloud_url" => "https://server_1.emmer.cloud"
}}
```

### Heartbeat

```elixir
# Start automatic heartbeat (recommended)
EmmerCloud.Client.start_heartbeat(server_id, cloud_url)

# Manual ping
EmmerCloud.Client.ping_cloud(server_id, cloud_url)
```

### Unregistration

```elixir
# Unregister when shutting down
EmmerCloud.Client.unregister_from_cloud(server_id, cloud_url)
```

## Integration with Local Emmer

To integrate cloud registration into your local Emmer server, add this to your application startup:

```elixir
# In your local Emmer application.ex
def start(_type, _args) do
  children = [
    # ... your existing children
  ]

  {:ok, pid} = Supervisor.start_link(children, opts)

  # Register with cloud proxy
  case EmmerCloud.Client.register_with_cloud(
    "My Site",
    "http://localhost:4116",
    "http://localhost:4000"
  ) do
    {:ok, response} ->
      Logger.info("Registered with cloud proxy: #{response["cloud_url"]}")

      # Start heartbeat
      EmmerCloud.Client.start_heartbeat(
        response["server_id"],
        "http://localhost:4000"
      )

    {:error, reason} ->
      Logger.warning("Failed to register with cloud: #{reason}")
  end

  {:ok, pid}
end
```

## Configuration

### Environment Variables

```bash
# Cloud domain (default: emmer.cloud)
export CLOUD_DOMAIN=your-domain.com

# Database pool size (default: 5)
export POOL_SIZE=10
```

### Production Deployment

For production deployment:

1. **Set up a domain** and configure DNS for wildcard subdomains
2. **Configure SSL certificates** for your domain and wildcard subdomains
3. **Set environment variables**:
   ```bash
   export CLOUD_DOMAIN=your-domain.com
   export SECRET_KEY_BASE=your-secret-key
   ```
4. **Deploy with your preferred method** (Docker, Heroku, etc.)

## Development

### Running Tests

```bash
mix test
```

### Database

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Reset database
mix ecto.reset
```

### Live Dashboard

Access the Phoenix LiveDashboard at `http://localhost:4000/dev/dashboard` for monitoring and debugging.

## Security Considerations

- The cloud proxy acts as a reverse proxy to your local server
- No files are stored on the cloud server
- All content is proxied in real-time
- Consider implementing authentication for production use
- Use HTTPS in production

## Troubleshooting

### Common Issues

1. **Registration fails**
   - Check that the cloud proxy is running
   - Verify the local URL is accessible
   - Check network connectivity

2. **Preview doesn't load**
   - Ensure your local Emmer server is running
   - Check that the file exists in your local build
   - Verify the server ID matches

3. **Links don't work**
   - The cloud proxy should automatically rewrite links
   - Check that your local server's link rewriting is working
   - Verify the subdomain is correct

### Logs

Check the logs for both the cloud proxy and your local server:

```bash
# Cloud proxy logs
tail -f log/dev.log

# Local server logs
tail -f log/dev.log
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License.
