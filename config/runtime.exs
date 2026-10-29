import Config

if System.get_env("PHX_SERVER") do
  config :phixem, PhixemWeb.Endpoint, server: true
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "8080")

  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For Azure Container Apps use /tmp/phixem.db
      """

  config :phixem, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :phixem, Phixem.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "1"),
    journal_mode: :wal,
    busy_timeout: 5_000

  config :phixem, PhixemWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    check_origin: ["https://#{host}"],
    force_ssl: [rewrite_on: [:x_forwarded_proto], exclude: ["/health"]]

  account = System.get_env("LITESTREAM_AZURE_ACCOUNT_NAME")
  key = System.get_env("LITESTREAM_AZURE_ACCOUNT_KEY")
  container = System.get_env("LITESTREAM_AZURE_CONTAINER")
  replica_path = System.get_env("LITESTREAM_AZURE_PATH") || "/phixem.db"

  if is_binary(account) and account != "" and is_binary(key) and key != "" and
       is_binary(container) and container != "" do
    replica_path =
      if String.starts_with?(replica_path, "/"), do: replica_path, else: "/" <> replica_path

    config :phixem, Litestream,
      repo: Phixem.Repo,
      bin_path: System.get_env("LITESTREAM_BIN") || "/usr/local/bin/litestream",
      strategy: %Litestream.Strategy.AzureBlobStorage{
        storage_account: account,
        account_key: key,
        container_name: container,
        path: replica_path
      }
  end
end
