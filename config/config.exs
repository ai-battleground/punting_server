# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :punting_server,
  ecto_repos: [PuntingServer.Repo]

# Configures the endpoint
config :punting_server, PuntingServerWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "xolPdQtujzGCK+6WrA+YYmpoJXAwJu/0Rz4+PTGiawQoWlTbi1TcjQKuBmYG5YYB",
  render_errors: [view: PuntingServerWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: PuntingServer.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
