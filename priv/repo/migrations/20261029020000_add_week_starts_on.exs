defmodule Phixem.Repo.Migrations.AddWeekStartsOn do
  use Ecto.Migration

  def change do
    alter table(:nfl_weeks) do
      add :starts_on, :date
    end

    execute(
      "UPDATE nfl_weeks SET starts_on = '2026-10-18' WHERE number = 7 AND starts_on IS NULL",
      "UPDATE nfl_weeks SET starts_on = NULL WHERE number = 7"
    )

    execute(
      "UPDATE nfl_weeks SET starts_on = '2026-10-25' WHERE number = 8 AND starts_on IS NULL",
      "UPDATE nfl_weeks SET starts_on = NULL WHERE number = 8"
    )

    create unique_index(:nfl_weeks, [:starts_on])
    drop unique_index(:nfl_weeks, [:tab])

    execute(
      "CREATE UNIQUE INDEX nfl_weeks_one_upcoming_tab ON nfl_weeks(tab) WHERE tab = 'upcoming'",
      "DROP INDEX nfl_weeks_one_upcoming_tab"
    )

    execute(
      "CREATE UNIQUE INDEX nfl_weeks_one_last_week_tab ON nfl_weeks(tab) WHERE tab = 'last_week'",
      "DROP INDEX nfl_weeks_one_last_week_tab"
    )
  end
end
