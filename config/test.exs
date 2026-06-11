import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :island_pulse, IslandPulse.Repo,
  username: "island_pulse",
  password: "island_pulse_dev_pass",
  hostname: "localhost",
  database: "island_pulse_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :island_pulse, IslandPulseWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "wxBl4LBtM3nYqLNLPQIDK35wjuzBmb3blbFXmtk4CVKYinhVzJiSuBxUOsxCf/sU",
  server: false

# In test we don't send emails
config :island_pulse, IslandPulse.Mailer, adapter: Swoosh.Adapters.Test

# Oban test config (no crontab in tests)
config :island_pulse, Oban,
  engine: Oban.Engines.Basic,
  repo: IslandPulse.Repo,
  queues: [default: 5, polling: 5, alerts: 3]

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
