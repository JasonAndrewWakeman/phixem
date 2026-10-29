defmodule Phixem.SqliteReplica do
  @moduledoc """
  Restores the local SQLite file from Litestream before Ecto opens it.

  Azure Container Apps scale-to-zero wipes ephemeral disk. Without this step,
  Repo would create an empty database and Litestream would not restore.
  """

  require Logger

  @spec restore() :: :ok
  def restore do
    case Application.get_env(:phixem, Litestream) do
      nil -> :ok
      config -> do_restore(config)
    end
  end

  defp do_restore(config) do
    repo = Keyword.fetch!(config, :repo)
    database = Keyword.fetch!(repo.config(), :database)
    bin = Keyword.get(config, :bin_path, "litestream")
    strategy = Keyword.fetch!(config, :strategy)
    replica_url = abs_url(strategy)

    database |> Path.dirname() |> File.mkdir_p!()

    if File.exists?(database) do
      Logger.info("SQLite file already present at #{database}; skipping Litestream restore")
      :ok
    else
      Logger.info("Restoring SQLite from #{replica_url} if a replica exists")

      {output, status} =
        System.cmd(
          bin,
          ["restore", "-if-replica-exists", "-o", database, replica_url],
          stderr_to_stdout: true,
          env: [{"LITESTREAM_AZURE_ACCOUNT_KEY", strategy.account_key}]
        )

      if status == 0 do
        Logger.info("Litestream restore finished: #{String.trim(output)}")
      else
        Logger.warning("Litestream restore returned #{status}: #{String.trim(output)}")
      end

      :ok
    end
  end

  defp abs_url(%{storage_account: account, container_name: container, path: path}) do
    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path
    "abs://#{account}@#{container}#{path}"
  end
end
