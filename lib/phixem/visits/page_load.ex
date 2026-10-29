defmodule Phixem.Visits.PageLoad do
  use Ecto.Schema

  schema "page_loads" do
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
