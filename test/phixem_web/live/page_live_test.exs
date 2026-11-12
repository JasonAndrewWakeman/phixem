defmodule PhixemWeb.PageLiveTest do
  use PhixemWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    Phixem.Pickem.seed!()
    :ok
  end

  test "home page defaults to the current pickem week and can select others", %{conn: conn} do
    default = Phixem.Pickem.default_week_number()
    week = Phixem.Pickem.get_week(default)
    [matchup | _] = Phixem.Pickem.Week.matchup_list(week)

    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "ENTRIES:"
    assert html =~ "TOTAL POT:"
    assert html =~ "header-stat-value"
    refute html =~ "Coins Won\" represents the total pot"
    assert html =~ "Week #{default}"
    assert html =~ matchup
    assert html =~ "PERFECT"
    refute html =~ "NE@SEA"

    html = render_click(view, "select_week", %{"number" => "1"})
    assert html =~ "NE@SEA"
    assert html =~ "SEA"
    assert html =~ "41"
    refute html =~ "31-10"
    refute html =~ "CAR@GB"

    assert {:ok, _} = Phixem.Pickem.save_perfect_winners(8, %{"CAR@GB" => "GB"}, "42")
    html = render_click(view, "select_week", %{"number" => "8"})
    assert html =~ "42"

    assert {:ok, _} = Phixem.Pickem.lock_week(8)
    html = render_click(view, "select_week", %{"number" => "8"})
    assert html =~ "Week locked! the current entries and total pot are final for week 8"
    refute html =~ "The list sorts based on # correct"
  end

  test "finalized week paints first place metallic gold and tied-correct misses silver", %{conn: conn} do
    week = Phixem.Pickem.get_week(8)
    picks = home_picks(week)

    {:ok, _} =
      Phixem.Pickem.create_entry(8, %{"username" => "Neo", "winners" => picks, "tie_breaker" => "44"})

    {:ok, _} =
      Phixem.Pickem.create_entry(8, %{"username" => "Trinity", "winners" => picks, "tie_breaker" => "60"})

    {:ok, _} =
      Phixem.Pickem.create_entry(8, %{
        "username" => "Morpheus",
        "winners" => away_picks(week),
        "tie_breaker" => "45"
      })

    {:ok, view, html} = live(conn, ~p"/?week=8")
    refute html =~ ~s(class="place-first")
    refute html =~ ~s(class="place-silver")

    {:ok, _} = Phixem.Pickem.save_perfect_winners(8, picks, "45")
    html = render(view)
    assert html =~ ~r{class="place-first"><th>Neo</th>}
    assert html =~ ~r{class="place-silver"><th>Trinity</th>}
    refute html =~ ~r{class="place-first"><th>Morpheus</th>}
    refute html =~ ~r{class="place-silver"><th>Morpheus</th>}
    refute html =~ ~r{class="place-first"><th>PERFECT</th>}
  end

  test "name search is case-insensitive and starts after two characters", %{conn: conn} do
    week = Phixem.Pickem.get_week(8)
    picks = home_picks(week)

    {:ok, _} =
      Phixem.Pickem.create_entry(8, %{"username" => "Neo", "winners" => picks, "tie_breaker" => "44"})

    {:ok, _} =
      Phixem.Pickem.create_entry(8, %{"username" => "Trinity", "winners" => picks, "tie_breaker" => "60"})

    {:ok, view, html} = live(conn, ~p"/?week=8")
    assert html =~ ~s(placeholder="search entry by name")

    html = render_change(form(view, "#entry-search"), %{"q" => "n"})
    refute html =~ "search-hit"

    html = render_change(form(view, "#entry-search"), %{"q" => "NE"})
    assert html =~ ~r{class="[^"]*search-hit[^"]*"><th>Neo</th>}
    refute html =~ ~r{class="[^"]*search-hit[^"]*"><th>Trinity</th>}
  end

  test "GET /health still works", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert text_response(conn, 200) == "ok"
  end

  defp home_picks(week) do
    Map.new(Phixem.Pickem.Week.matchup_list(week), fn matchup ->
      {_away, home} = Phixem.Pickem.Week.matchup_teams(matchup)
      {matchup, home}
    end)
  end

  defp away_picks(week) do
    Map.new(Phixem.Pickem.Week.matchup_list(week), fn matchup ->
      {away, _home} = Phixem.Pickem.Week.matchup_teams(matchup)
      {matchup, away}
    end)
  end
end
