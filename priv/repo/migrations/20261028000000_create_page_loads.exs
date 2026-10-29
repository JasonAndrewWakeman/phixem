defmodule Phixem.Repo.Migrations.CreatePageLoads do
  use Ecto.Migration

  def change do
    create table(:page_loads) do
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:page_loads, [:inserted_at])
  end
end
