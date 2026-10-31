defmodule PhixemWeb.AdminHTML do
  use PhixemWeb, :html

  alias Phixem.Pickem.Week

  embed_templates "admin_html/*"

  def selected_winner(winners, matchup), do: winners[matchup]

  def selected_tie?(winners, matchup) do
    selected_winner(winners, matchup) in [nil, ""]
  end

  def perfect_tie_breaker(week) do
    cond do
      is_integer(week.tie_breaker_value) -> Integer.to_string(week.tie_breaker_value)
      is_binary(week.mnf_score) and week.mnf_score != "" -> week.mnf_score
      true -> ""
    end
  end

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
