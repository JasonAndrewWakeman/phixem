defmodule Phixem.PickemTest do
  use Phixem.DataCase

  alias Phixem.Pickem
  alias Phixem.Pickem.Week

  setup do
    Pickem.seed!()
    :ok
  end

  test "seeds all 18 regular-season weeks from the ESPN snapshot" do
    weeks = Pickem.list_weeks()
    assert Enum.map(weeks, & &1.number) == Enum.to_list(1..18)
    assert Enum.all?(weeks, &(&1.starts_on && Date.day_of_week(&1.starts_on) == 7))

    week1 = Pickem.get_week(1)
    assert "NE@SEA" in Phixem.Pickem.Week.matchup_list(week1)
    assert week1.complete
    perfect = Enum.find(week1.entries, & &1.winners_row)
    assert Phixem.Pickem.Entry.pick_map(perfect)["NE@SEA"] == "SEA"
    assert perfect.correct_choices == length(Phixem.Pickem.Week.matchup_list(week1))

    week8 = Pickem.get_week(8)
    refute week8.complete
    assert "CAR@GB" in Phixem.Pickem.Week.matchup_list(week8)
    assert Pickem.default_week_number() == 8
  end

  test "seed_season! keeps extra entries while refreshing week headers" do
    week = Pickem.get_week(8)

    %Phixem.Pickem.Entry{}
    |> Phixem.Pickem.Entry.changeset(%{
      week_id: week.id,
      username: "Neo",
      winners_row: false,
      picks: "{}"
    })
    |> Repo.insert!()

    assert :ok = Pickem.seed_season!()
    refreshed = Pickem.get_week(8)
    assert Enum.any?(refreshed.entries, &(&1.username == "Neo"))
    assert Enum.any?(refreshed.entries, &(&1.username == "PERFECT"))
  end

  test "save_perfect_winners updates PERFECT and survives a later season seed" do
    assert {:ok, entry} = Pickem.save_perfect_winners(8, %{"CAR@GB" => "GB", "BAL@BUF" => "BUF"})
    picks = Phixem.Pickem.Entry.pick_map(entry)
    assert picks["CAR@GB"] == "GB"
    assert picks["BAL@BUF"] == "BUF"
    assert entry.correct_choices == 2

    assert :ok = Pickem.seed_season!()
    refreshed = Pickem.get_week(8)
    perfect = Enum.find(refreshed.entries, & &1.winners_row)
    assert Phixem.Pickem.Entry.pick_map(perfect)["CAR@GB"] == "GB"
  end

  test "save_perfect_winners rejects a team that is not in the matchup" do
    assert {:error, :invalid_winners} = Pickem.save_perfect_winners(8, %{"CAR@GB" => "DAL"})
  end

  test "create_entry adds a player row and gives PERFECT 9 coins per entry" do
    week = Pickem.get_week(8)
    picks = home_picks(week)

    Enum.each(1..10, fn n ->
      assert {:ok, entry} =
               Pickem.create_entry(8, %{
                 "username" => "player#{n}",
                 "winners" => picks,
                 "tie_breaker" => "45"
               })

      assert entry.username == "player#{n}"
      assert entry.tie_breaker == "45"
    end)

    week = Pickem.get_week(8)
    perfect = Enum.find(week.entries, & &1.winners_row)
    assert perfect.coins_won == 90
    assert Enum.count(week.entries, &(&1.winners_row == false)) == 10
  end

  test "updating PERFECT scores, sorts, and pays a unique leader the full pot" do
    week = Pickem.get_week(8)
    set_mnf!(week, 45)

    {:ok, _} =
      Pickem.create_entry(8, %{
        "username" => "Neo",
        "winners" => home_picks(week),
        "tie_breaker" => "40"
      })

    {:ok, _} =
      Pickem.create_entry(8, %{
        "username" => "Trinity",
        "winners" => away_picks(week),
        "tie_breaker" => "45"
      })

    {:ok, _} = Pickem.save_perfect_winners(8, home_picks(week))

    [perfect, neo, trinity] = names(Pickem.get_week(8))
    assert perfect.username == "PERFECT"
    assert perfect.correct_choices == length(Phixem.Pickem.Week.matchup_list(Pickem.get_week(8)))
    assert neo.username == "Neo"
    assert trinity.username == "Trinity"
    assert neo.correct_choices > trinity.correct_choices
    assert neo.coins_won == 18
    assert trinity.coins_won == 0
    assert perfect.coins_won == 18
  end

  test "tied # correct get a free entry and the closest MNF guess wins the remainder" do
    week = Pickem.get_week(8)
    set_mnf!(week, 45)
    picks = home_picks(week)

    {:ok, _} = Pickem.create_entry(8, %{"username" => "Neo", "winners" => picks, "tie_breaker" => "44"})
    {:ok, _} = Pickem.create_entry(8, %{"username" => "Trinity", "winners" => picks, "tie_breaker" => "60"})
    {:ok, _} = Pickem.create_entry(8, %{"username" => "Morpheus", "winners" => away_picks(week), "tie_breaker" => "45"})
    {:ok, _} = Pickem.save_perfect_winners(8, picks)

    week = Pickem.get_week(8)
    neo = Enum.find(week.entries, &(&1.username == "Neo"))
    trinity = Enum.find(week.entries, &(&1.username == "Trinity"))
    morpheus = Enum.find(week.entries, &(&1.username == "Morpheus"))

    assert neo.correct_choices == trinity.correct_choices
    assert neo.correct_choices > morpheus.correct_choices
    # pot 27, two leaders get 10 each, remainder 7 to closest (Neo)
    assert neo.coins_won == 17
    assert trinity.coins_won == 10
    assert morpheus.coins_won == 0
    assert names(week) |> Enum.map(& &1.username) == ["PERFECT", "Neo", "Trinity", "Morpheus"]
  end

  test "equally close tie-breakers split the remainder" do
    week = Pickem.get_week(8)
    set_mnf!(week, 45)
    picks = home_picks(week)

    {:ok, _} = Pickem.create_entry(8, %{"username" => "Neo", "winners" => picks, "tie_breaker" => "40"})
    {:ok, _} = Pickem.create_entry(8, %{"username" => "Trinity", "winners" => picks, "tie_breaker" => "50"})
    {:ok, _} =
      Pickem.create_entry(8, %{"username" => "Morpheus", "winners" => away_picks(week), "tie_breaker" => "45"})

    {:ok, _} = Pickem.save_perfect_winners(8, picks)

    week = Pickem.get_week(8)
    neo = Enum.find(week.entries, &(&1.username == "Neo"))
    trinity = Enum.find(week.entries, &(&1.username == "Trinity"))
    morpheus = Enum.find(week.entries, &(&1.username == "Morpheus"))
    # pot 27, two leaders 10 each, remainder 7 split 4/3
    assert neo.coins_won + trinity.coins_won == 27
    assert neo.coins_won in [13, 14]
    assert trinity.coins_won in [13, 14]
    assert morpheus.coins_won == 0
  end

  defp home_picks(week) do
    Map.new(Week.matchup_list(week), fn matchup ->
      {_away, home} = Week.matchup_teams(matchup)
      {matchup, home}
    end)
  end

  defp away_picks(week) do
    Map.new(Week.matchup_list(week), fn matchup ->
      {away, _home} = Week.matchup_teams(matchup)
      {matchup, away}
    end)
  end

  defp set_mnf!(week, total) do
    week
    |> Week.changeset(%{tie_breaker_value: total, mnf_score: "#{total}"})
    |> Repo.update!()
  end

  defp names(week), do: week.entries
end
