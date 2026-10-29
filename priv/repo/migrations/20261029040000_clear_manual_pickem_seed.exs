defmodule Phixem.Repo.Migrations.ClearManualPickemSeed do
  use Ecto.Migration

  def up do
    execute """
    DELETE FROM nfl_entries
    WHERE winners_row = 0
      AND week_id IN (SELECT id FROM nfl_weeks WHERE number = 8)
    """

    execute """
    UPDATE nfl_entries
    SET coins_won = 0
    WHERE username = 'PERFECT'
      AND week_id IN (SELECT id FROM nfl_weeks WHERE number = 8)
    """
  end

  def down do
    :ok
  end
end
