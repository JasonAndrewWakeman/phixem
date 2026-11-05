defmodule PhixemWeb.AdminControllerTest do
  use PhixemWeb.ConnCase

  alias Phixem.Pickem

  test "GET /broncosAdmin shows a passphrase form when unauthenticated", %{conn: conn} do
    conn = get(conn, ~p"/broncosAdmin")
    html = html_response(conn, 200)
    assert html =~ "passphrase"
    refute html =~ ~s(id="admin-ok")
  end

  test "POST /broncosAdmin rejects an invalid passphrase", %{conn: conn} do
    conn = post(conn, ~p"/broncosAdmin", %{"passphrase" => "nope"})
    html = html_response(conn, 401)
    assert html =~ "Invalid passphrase"
    refute html =~ ~s(id="admin-ok")
  end

  test "unlocked admin hides PERFECT until SELECT WINNERS and lists it after the entry form", %{
    conn: conn
  } do
    Pickem.seed!()
    conn = unlock(conn) |> get(~p"/broncosAdmin?week=1")
    html = html_response(conn, 200)
    assert html =~ ~s(id="admin-ok")
    assert html =~ "Create entry"
    assert html =~ "SELECT WINNERS"
    assert html =~ "Lock Week"
    assert html =~ "data-confirm"
    assert html =~ "Week 1"
    assert html =~ "This is not reversible"
    assert html =~ "NE@SEA"
    assert html =~ ~s(value="SEA")
    assert html =~ "TIE"
    refute html =~ ~r/details[^>]*open/
    create_at = :binary.match(html, "Create entry") |> elem(0)
    winners_at = :binary.match(html, "SELECT WINNERS") |> elem(0)
    assert create_at < winners_at
    refute html =~ "Complete week"
  end

  test "admin can save PERFECT winners and they appear on the board", %{conn: conn} do
    Pickem.seed!()
    conn = unlock(conn)

    conn =
      post(conn, ~p"/broncosAdmin/perfect", %{
        "week" => "8",
        "winners" => %{"CAR@GB" => "CAR", "BAL@BUF" => "BUF"},
        "tie_breaker" => "42"
      })

    assert redirected_to(conn) == ~p"/broncosAdmin?week=8"

    conn = get(recycle(conn), ~p"/broncosAdmin?week=8")
    html = html_response(conn, 200)
    assert html =~ "PERFECT winners saved"
    assert html =~ ~s(value="CAR")

    week = Pickem.get_week(8)
    perfect = Enum.find(week.entries, & &1.winners_row)
    assert Phixem.Pickem.Entry.pick_map(perfect)["CAR@GB"] == "CAR"
    assert perfect.tie_breaker == "42"
    assert week.tie_breaker_value == 42
    assert week.mnf_score == "42"
  end

  test "admin can mark a PERFECT matchup as TIE and the board cell is blank", %{conn: conn} do
    Pickem.seed!()
    conn = unlock(conn)

    conn =
      post(conn, ~p"/broncosAdmin/perfect", %{
        "week" => "8",
        "winners" => %{"CAR@GB" => "CAR"}
      })

    assert redirected_to(conn) == ~p"/broncosAdmin?week=8"

    conn =
      recycle(conn)
      |> post(~p"/broncosAdmin/perfect", %{
        "week" => "8",
        "winners" => %{"CAR@GB" => "TIE"}
      })

    assert redirected_to(conn) == ~p"/broncosAdmin?week=8"

    week = Pickem.get_week(8)
    perfect = Enum.find(week.entries, & &1.winners_row)
    assert Phixem.Pickem.Entry.pick_map(perfect)["CAR@GB"] == ""
  end

  test "admin can create a manual entry for the selected week", %{conn: conn} do
    Pickem.seed!()
    week = Pickem.get_week(8)
    winners = home_picks(week)
    conn = unlock(conn)

    conn =
      post(conn, ~p"/broncosAdmin/entries", %{
        "week" => "8",
        "username" => "Neo",
        "tie_breaker" => "41",
        "winners" => winners
      })

    assert redirected_to(conn) == ~p"/broncosAdmin?week=8"
    week = Pickem.get_week(8)
    neo = Enum.find(week.entries, &(&1.username == "Neo"))
    assert neo.tie_breaker == "41"
    assert is_nil(neo.coins_won)
    perfect = Enum.find(week.entries, & &1.winners_row)
    assert perfect.coins_won == 8.5
  end

  test "admin rejects a duplicate name for the same week", %{conn: conn} do
    Pickem.seed!()
    week = Pickem.get_week(8)
    winners = home_picks(week)
    conn = unlock(conn)

    conn =
      post(conn, ~p"/broncosAdmin/entries", %{
        "week" => "8",
        "username" => "Neo",
        "tie_breaker" => "41",
        "winners" => winners
      })

    conn =
      recycle(conn)
      |> post(~p"/broncosAdmin/entries", %{
        "week" => "8",
        "username" => " neo ",
        "tie_breaker" => "50",
        "winners" => winners
      })

    assert redirected_to(conn) == ~p"/broncosAdmin?week=8"
    conn = get(recycle(conn), ~p"/broncosAdmin?week=8")
    html = html_response(conn, 200)
    assert html =~ "neo already has an entry for week 8."
    assert html =~ ~s(value="50")
    assert Enum.count(Pickem.get_week(8).entries, &(&1.winners_row == false)) == 1
  end

  test "admin entry save lists missing picks and tie-breaker", %{conn: conn} do
    Pickem.seed!()
    conn = unlock(conn)

    conn =
      post(conn, ~p"/broncosAdmin/entries", %{
        "week" => "8",
        "username" => "Neo",
        "tie_breaker" => "",
        "winners" => %{"CAR@GB" => "GB"}
      })

    assert redirected_to(conn) == ~p"/broncosAdmin?week=8"
    conn = get(recycle(conn), ~p"/broncosAdmin?week=8")
    html = html_response(conn, 200)
    assert html =~ "Missing:"
    assert html =~ "BAL@BUF"
    assert html =~ "Tie-breaker"
    refute html =~ "Missing: Name"
    assert html =~ ~s(value="Neo")
    assert html =~ ~s(value="GB")
    assert Enum.find(Pickem.get_week(8).entries, &(&1.username == "Neo")) == nil
  end

  test "admin can lock a week and then cannot add entries", %{conn: conn} do
    Pickem.seed!()
    week = Pickem.get_week(8)
    winners = home_picks(week)
    conn = unlock(conn)

    conn = post(conn, ~p"/broncosAdmin/lock", %{"week" => "8"})
    assert redirected_to(conn) == ~p"/broncosAdmin?week=8"
    assert Pickem.get_week(8).entries_locked

    conn = get(recycle(conn), ~p"/broncosAdmin?week=8")
    html = html_response(conn, 200)
    assert html =~ "Week locked! the current entries and total pot are final for week 8"
    refute html =~ "Create entry"
    refute html =~ "Lock Week"
    assert html =~ "SELECT WINNERS"

    conn =
      recycle(conn)
      |> post(~p"/broncosAdmin/entries", %{
        "week" => "8",
        "username" => "Neo",
        "tie_breaker" => "41",
        "winners" => winners
      })

    assert redirected_to(conn) == ~p"/broncosAdmin?week=8"
    conn = get(recycle(conn), ~p"/broncosAdmin?week=8")
    html = html_response(conn, 200)
    assert html =~ "Week 8 is locked. No new entries can be added."
    assert Enum.find(Pickem.get_week(8).entries, &(&1.username == "Neo")) == nil
  end

  defp home_picks(week) do
    Map.new(Phixem.Pickem.Week.matchup_list(week), fn matchup ->
      {_away, home} = Phixem.Pickem.Week.matchup_teams(matchup)
      {matchup, home}
    end)
  end

  defp unlock(conn) do
    conn
    |> post(~p"/broncosAdmin", %{"passphrase" => "test-passphrase"})
    |> recycle()
  end
end
