defmodule Phixem.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Phixem.SqliteReplica.restore()

    children =
      [
        PhixemWeb.Telemetry,
        Phixem.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:phixem, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:phixem, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Phixem.PubSub},
        litestream_child(),
        PhixemWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: Phixem.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)
    Phixem.Pickem.seed_if_empty!()
    {:ok, pid}
  end

  @impl true
  def config_change(changed, _new, removed) do
    PhixemWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp litestream_child do
    case Application.get_env(:phixem, Litestream) do
      nil -> nil
      config -> {Litestream, config}
    end
  end

  defp skip_migrations? do
    System.get_env("RELEASE_NAME") == nil
  end
end
