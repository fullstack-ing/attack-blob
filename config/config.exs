# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :attack_blob,
  generators: [timestamp_type: :utc_datetime]

# Default CORS configuration (can be overridden at runtime)
config :attack_blob, :cors,
  origins: ~r/.*/,
  max_age: 600,
  allow_credentials: true

# Configures the endpoint
config :attack_blob, AttackBlobWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: AttackBlobWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AttackBlob.PubSub,
  live_view: [signing_salt: "FqIm/yPR"]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
