use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :punting_server, PuntingServerWeb.Endpoint,
  http: [port: 4001],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Configure your database
config :punting_server, PuntingServer.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "punting_server_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :punting_server,
  ip: {127,0,0,1},
  port: 7190
