import Config

config :logger, level: :info

# Must be set at compile time. Phoenix marks Endpoint :force_ssl as compile_env;
# setting it only in runtime.exs aborts boot in a release.
config :phixem, PhixemWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto], exclude: ["/health"]]
