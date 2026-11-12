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
    assert week1.mnf_score == "41"
    assert week1.tie_breaker_value == 41
    perfect = Enum.find(week1.entries, & &1.winners_row)
    assert Phixem.Pickem.Entry.pick_map(perfect)["NE@SEA"] == "SEA"
    assert perfect.tie_breaker == "41"
    assert perfect.correct_choices == length(Phixem.Pickem.Week.matchup_list(week1))

    week8 = Pickem.get_week(8)
    refute week8.complete
    assert "CAR@GB" in Phixem.Pickem.Week.matchup_list(week8)
    assert Pickem.default_week_number(~U[2026-10-28 18:00:00Z]) == 8
    week8_perfect = Enum.find(week8.entries, & &1.winners_row)
    assert Phixem.Pickem.Entry.pick_map(week8_perfect) == %{}
    assert week8_perfect.tie_breaker in [nil, ""]
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

  test "save_perfect_winners stores the Monday night total and seed does not wipe it" do
    assert {:ok, entry} = Pickem.save_perfect_winners(8, %{"CAR@GB" => "GB"}, "42")
    assert entry.tie_breaker == "42"

    week = Pickem.get_week(8)
    assert week.tie_breaker_value == 42
    assert week.mnf_score == "42"

    assert :ok = Pickem.seed_season!()
    week = Pickem.get_week(8)
    assert week.tie_breaker_value == 42
    assert week.mnf_score == "42"
  end

  test "save_perfect_winners rejects a non-numeric tie-breaker" do
    assert {:error, :invalid_tie_breaker} =
             Pickem.save_perfect_winners(8, %{"CAR@GB" => "GB"}, "final")
  end

  test "save_perfect_winners stores TIE as a blank pick" do
    assert {:ok, _} = Pickem.save_perfect_winners(8, %{"CAR@GB" => "GB"})
    assert {:ok, entry} = Pickem.save_perfect_winners(8, %{"CAR@GB" => "TIE"})
    assert Phixem.Pickem.Entry.pick_map(entry)["CAR@GB"] == ""
    assert entry.correct_choices == 0
  end

  test "default_week_number flips to the next Sunday after Tuesday noon Eastern" do
    # Week 9 is Sunday Nov 8; week 10 is Sunday Nov 15.
    # Tuesday Nov 10 2026 is EST (UTC-5).
    assert Pickem.default_week_number(~U[2026-11-10 16:59:00Z]) == 9
    assert Pickem.default_week_number(~U[2026-11-10 17:00:00Z]) == 10
    assert Pickem.default_week_number(~U[2026-11-11 18:00:00Z]) == 10
    assert Pickem.default_week_number(~U[2026-11-15 17:00:00Z]) == 10
    assert Pickem.default_week_number(~U[2026-11-16 17:00:00Z]) == 10
    assert Pickem.default_week_number(~U[2026-11-17 16:59:00Z]) == 10
    assert Pickem.default_week_number(~U[2026-11-17 17:00:00Z]) == 11
  end

  test "create_entry requires a pick for every matchup and a tie-breaker" do
    week = Pickem.get_week(8)
    picks = home_picks(week) |> Map.delete("CAR@GB")

    assert {:error, {:missing_fields, missing}} =
             Pickem.create_entry(8, %{
               "username" => "Neo",
               "winners" => picks,
               "tie_breaker" => ""
             })

    assert "CAR@GB" in missing
    assert "Tie-breaker" in missing
    refute "Name" in missing
  end

  test "create_entry normalizes names and rejects a duplicate for the same week" do
    week = Pickem.get_week(8)
    picks = home_picks(week)

    assert {:ok, entry} =
             Pickem.create_entry(8, %{
               "username" => "  Neo  ",
               "winners" => picks,
               "tie_breaker" => "41"
             })

    assert entry.username == "Neo"

    assert {:error, {:duplicate_name, "NEO"}} =
             Pickem.create_entry(8, %{
               "username" => "NEO",
               "winners" => picks,
               "tie_breaker" => "50"
             })

    assert Enum.count(Pickem.get_week(8).entries, &(&1.username == "Neo")) == 1
  end

  test "lock_week blocks new entries and cannot be undone" do
    week = Pickem.get_week(8)
    picks = home_picks(week)

    assert {:ok, locked} = Pickem.lock_week(8)
    assert locked.entries_locked
    assert {:error, :already_locked} = Pickem.lock_week(8)
    assert {:error, :week_locked} =
             Pickem.create_entry(8, %{
               "username" => "Neo",
               "winners" => picks,
               "tie_breaker" => "41"
             })

    assert Enum.find(Pickem.get_week(8).entries, &(&1.username == "Neo")) == nil
  end

  test "create_entry adds a player row and gives PERFECT 8.5 coins per entry" do
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
    assert perfect.coins_won == 85.0
    assert Enum.count(week.entries, &(&1.winners_row == false)) == 10
    assert Enum.all?(week.entries, fn entry -> entry.winners_row or is_nil(entry.coins_won) end)

    {:ok, _} = Pickem.save_perfect_winners(8, home_picks(week), "45")
    week = Pickem.get_week(8)
    players = Enum.reject(week.entries, & &1.winners_row)
    assert Enum.all?(players, &(is_number(&1.coins_won) and &1.coins_won >= 0))
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
    assert neo.coins_won == 17.0
    assert trinity.coins_won == 0.0
    assert perfect.coins_won == 17.0
    roles = Pickem.highlight_roles(Pickem.get_week(8))
    assert roles[neo.id] == :first
    refute Map.has_key?(roles, trinity.id)
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
    # pot 25.5, two leaders get 10 each, remainder 5.5 to closest (Neo)
    assert neo.coins_won == 15.5
    assert trinity.coins_won == 10.0
    assert morpheus.coins_won == 0.0
    assert names(week) |> Enum.map(& &1.username) == ["PERFECT", "Neo", "Trinity", "Morpheus"]
    roles = Pickem.highlight_roles(week)
    assert roles[neo.id] == :first
    assert roles[trinity.id] == :silver
    refute Map.has_key?(roles, morpheus.id)
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
    # pot 25.5, two leaders 10 each, remainder 5.5 split 3/2.5
    assert neo.coins_won + trinity.coins_won == 25.5
    assert neo.coins_won in [12.5, 13.0]
    assert trinity.coins_won in [12.5, 13.0]
    assert morpheus.coins_won == 0.0
    roles = Pickem.highlight_roles(week)
    assert roles[neo.id] == :first
    assert roles[trinity.id] == :first
    refute Map.has_key?(roles, morpheus.id)
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
