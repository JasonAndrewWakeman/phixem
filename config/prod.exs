import Config

config :logger, level: :info

config :phixem, PhixemWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

# Must be set at compile time. Phoenix marks Endpoint :force_ssl as compile_env;
# setting it only in runtime.exs aborts boot in a release.
# Plug 1.20: path excludes are {:paths, ["/health"]}, not already-split path_info.
config :phixem, PhixemWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [paths: ["/health"]]
  ]
