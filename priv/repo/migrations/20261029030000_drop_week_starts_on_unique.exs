defmodule Phixem.Repo.Migrations.DropWeekStartsOnUnique do
  use Ecto.Migration

  def change do
    drop unique_index(:nfl_weeks, [:starts_on])
    create index(:nfl_weeks, [:starts_on])
  end
end
