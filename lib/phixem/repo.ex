defmodule Phixem.Repo do
  use Ecto.Repo,
    otp_app: :phixem,
    adapter: Ecto.Adapters.SQLite3
end
