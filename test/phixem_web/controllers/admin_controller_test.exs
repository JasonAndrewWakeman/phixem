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

  test "unlocked admin shows a prepopulated PERFECT form", %{conn: conn} do
    Pickem.seed!()
    conn = unlock(conn) |> get(~p"/broncosAdmin?week=1")
    html = html_response(conn, 200)
    assert html =~ ~s(id="admin-ok")
    assert html =~ "NE@SEA"
    assert html =~ ~s(value="SEA")
    assert html =~ ~s(checked)
    refute html =~ "Complete week"
  end

  test "admin can save PERFECT winners and they appear on the board", %{conn: conn} do
    Pickem.seed!()
    conn = unlock(conn)

    conn =
      post(conn, ~p"/broncosAdmin/perfect", %{
        "week" => "8",
        "winners" => %{"CAR@GB" => "CAR", "BAL@BUF" => "BUF"}
      })

    assert redirected_to(conn) == ~p"/broncosAdmin?week=8"

    conn = get(recycle(conn), ~p"/broncosAdmin?week=8")
    html = html_response(conn, 200)
    assert html =~ "PERFECT winners saved"
    assert html =~ ~s(value="CAR")

    week = Pickem.get_week(8)
    perfect = Enum.find(week.entries, & &1.winners_row)
    assert Phixem.Pickem.Entry.pick_map(perfect)["CAR@GB"] == "CAR"
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
    perfect = Enum.find(week.entries, & &1.winners_row)
    assert perfect.coins_won == 9
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
