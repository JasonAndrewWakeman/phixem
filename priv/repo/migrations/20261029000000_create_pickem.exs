defmodule Phixem.Repo.Migrations.CreatePickem do
  use Ecto.Migration

  def change do
    create table(:nfl_weeks) do
      add :number, :integer, null: false
      add :tab, :string, null: false
      add :title, :string, null: false
      add :matchups, :string, null: false
      add :complete, :boolean, null: false, default: false
      add :mnf_score, :string
      add :tie_breaker_value, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:nfl_weeks, [:number])
    create unique_index(:nfl_weeks, [:tab])

    create table(:nfl_entries) do
      add :week_id, references(:nfl_weeks, on_delete: :delete_all), null: false
      add :username, :string, null: false
      add :winners_row, :boolean, null: false, default: false
      add :picks, :string, null: false, default: "{}"
      add :tie_breaker, :string
      add :correct_choices, :integer
      add :coins_won, :integer
      add :total_coins_won, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:nfl_entries, [:week_id])
  end
end
