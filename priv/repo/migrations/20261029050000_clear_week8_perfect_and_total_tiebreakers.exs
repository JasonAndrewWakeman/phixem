defmodule Phixem.Repo.Migrations.ClearWeek8PerfectAndTotalTiebreakers do
  use Ecto.Migration

  def up do
    execute """
    UPDATE nfl_weeks
    SET mnf_score = CAST(tie_breaker_value AS TEXT)
    WHERE tie_breaker_value IS NOT NULL
    """

    execute """
    UPDATE nfl_entries
    SET tie_breaker = (
      SELECT CAST(w.tie_breaker_value AS TEXT)
      FROM nfl_weeks w
      WHERE w.id = nfl_entries.week_id
    )
    WHERE winners_row = 1
      AND week_id IN (
        SELECT id FROM nfl_weeks WHERE tie_breaker_value IS NOT NULL
      )
    """

    execute """
    UPDATE nfl_entries
    SET picks = '{}',
        tie_breaker = NULL,
        correct_choices = 0,
        coins_won = 0
    WHERE username = 'PERFECT'
      AND week_id IN (SELECT id FROM nfl_weeks WHERE number = 8)
    """
  end

  def down do
    :ok
  end
end
