import Config

# We run a server during integration tests on port 4002
config :attack_blob, AttackBlobWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "1QeD6J7fjTrW6Is/RB55XIEuWaueG64pBKjhwIiLp9x/BQTQ7LVkuNybl68RWHsJ",
  server: true

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
