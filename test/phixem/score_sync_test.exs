defmodule Phixem.ScoreSyncTest do
  use Phixem.DataCase

  alias Phixem.{Eastern, Espn, Pickem, ScoreSync}

  setup do
    Pickem.seed!()
    :ok
  end

  test "score fetch windows are Thursday night and Sunday noon through Tuesday 3am Eastern" do
    # EST (UTC-5) after 2026-11-01.
    assert Eastern.score_fetch_window?(~U[2026-11-13 03:00:00Z])
    assert Eastern.score_fetch_window?(~U[2026-11-13 07:59:00Z])
    refute Eastern.score_fetch_window?(~U[2026-11-13 08:00:00Z])
    assert Eastern.score_fetch_window?(~U[2026-11-15 17:00:00Z])
    assert Eastern.score_fetch_window?(~U[2026-11-16 12:00:00Z])
    assert Eastern.score_fetch_window?(~U[2026-11-17 07:59:00Z])
    refute Eastern.score_fetch_window?(~U[2026-11-17 08:00:00Z])
    refute Eastern.score_fetch_window?(~U[2026-11-11 18:00:00Z])
  end

  test "sync fills only blank PERFECT picks from finals and skips the API when already complete" do
    week = Pickem.get_week(8)
    {:ok, _} = Pickem.save_perfect_winners(8, %{"CAR@GB" => "CAR"})

    fetch = fn _week ->
      {:ok,
       %{
         winners: %{"CAR@GB" => "GB", "BAL@BUF" => "BUF"},
         mnf_total: 41
       }}
    end

    assert {:ok, _} = ScoreSync.sync_week(week, fetch: fetch)
    week = Pickem.get_week(8)
    perfect = Enum.find(week.entries, & &1.winners_row)
    picks = Phixem.Pickem.Entry.pick_map(perfect)
    assert picks["CAR@GB"] == "CAR"
    assert picks["BAL@BUF"] == "BUF"
    assert week.tie_breaker_value == 41
    refute Pickem.week_results_final?(week)

    winners =
      Map.new(Phixem.Pickem.Week.matchup_list(week), fn matchup ->
        {_away, home} = Phixem.Pickem.Week.matchup_teams(matchup)
        {matchup, home}
      end)

    {:ok, _} = Pickem.save_perfect_winners(8, winners, "50")

    assert {:ok, :already_final} =
             ScoreSync.sync_week(Pickem.get_week(8), fetch: fn _ -> flunk("should not fetch") end)
  end

  test "espn parser maps finals onto AWAY@HOME keys and monday combined score" do
    week = Pickem.get_week(8)

    body = %{
      "events" => [
        event("2026-11-01T18:00:00Z", "CAR", "GB", "17", "24", true, "away"),
        event("2026-11-02T18:00:00Z", "BAL", "BUF", "10", "10", false, nil),
        event("2026-11-03T01:20:00Z", "CHI", "SEA", "20", "21", true, "home")
      ]
    }

    parsed = Espn.parse_scoreboard(body, week)
    assert parsed.winners["CAR@GB"] == "CAR"
    refute Map.has_key?(parsed.winners, "BAL@BUF")
    assert parsed.winners["CHI@SEA"] == "SEA"
    assert parsed.mnf_total == 41
  end

  defp event(date, away, home, away_score, home_score, completed, winner) do
    %{
      "date" => date,
      "competitions" => [
        %{
          "date" => date,
          "status" => %{"type" => %{"completed" => completed, "state" => if(completed, do: "post", else: "in")}},
          "competitors" => [
            competitor("away", away, away_score, winner == "away"),
            competitor("home", home, home_score, winner == "home")
          ]
        }
      ]
    }
  end

  defp competitor(home_away, abbr, score, winner?) do
    %{
      "homeAway" => home_away,
      "score" => score,
      "winner" => winner?,
      "team" => %{"abbreviation" => abbr}
    }
  end
end
