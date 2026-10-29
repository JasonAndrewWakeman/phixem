import Config

config :phixem,
  ecto_repos: [Phixem.Repo],
  generators: [timestamp_type: :utc_datetime]

config :phixem, PhixemWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PhixemWeb.ErrorHTML, json: PhixemWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Phixem.PubSub,
  live_view: [signing_salt: "pL9sR4wY"]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
