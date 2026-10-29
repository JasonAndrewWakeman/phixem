defmodule PhixemWeb.AdminHTML do
  use PhixemWeb, :html

  alias Phixem.Pickem.Week

  embed_templates "admin_html/*"

  def selected_winner(winners, matchup), do: winners[matchup]

  def away_team(matchup) do
    case Week.matchup_teams(matchup) do
      {away, _home} -> away
      _ -> ""
    end
  end

  def home_team(matchup) do
    case Week.matchup_teams(matchup) do
      {_away, home} -> home
      _ -> ""
    end
  end
end
