defmodule Phixem.Repo.Migrations.AddWeekEntriesLocked do
  use Ecto.Migration

  def change do
    alter table(:nfl_weeks) do
      add :entries_locked, :boolean, null: false, default: false
    end
  end
end
