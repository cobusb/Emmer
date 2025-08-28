# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure your database
config :emmer, Emmer.Repo,
  database: Path.expand("../emmer_dev.db", Path.dirname(__ENV__.file)),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

# Configure your application
config :emmer,
  namespace: Emmer,
  ecto_repos: [Emmer.Repo],
  generators: [timestamp_type: :utc_datetime]

config :esbuild,
  version: "0.17.11",
  emmer: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  emmer: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure the endpoint
config :emmer, EmmerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EmmerWeb.ErrorHTML, json: EmmerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Emmer.PubSub,
  live_view: [signing_salt: "your-signing-salt-here"]

# Configure the mailer
config :emmer, Emmer.Mailer, adapter: Swoosh.Adapters.Local

# Configure the logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
