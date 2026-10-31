defmodule Phixem.Repo.Migrations.UniqueEntryUsernamePerWeek do
  use Ecto.Migration

  def up do
    execute """
    DELETE FROM nfl_entries
    WHERE id NOT IN (
      SELECT MIN(id) FROM nfl_entries GROUP BY week_id, lower(username)
    )
    """

    execute """
    CREATE UNIQUE INDEX nfl_entries_week_username_lower
    ON nfl_entries (week_id, lower(username))
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS nfl_entries_week_username_lower"
  end
end
