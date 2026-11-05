defmodule PhixemWeb.PageLiveTest do
  use PhixemWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    Phixem.Pickem.seed!()
    :ok
  end

  test "home page defaults to the first open week and can select others", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "ENTRIES:"
    assert html =~ "TOTAL POT:"
    assert html =~ "header-stat-value"
    refute html =~ "Coins Won\" represents the total pot"
    assert html =~ "Week 8"
    assert html =~ "CAR@GB"
    assert html =~ "CHI@SEA"
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

  test "GET /health still works", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert text_response(conn, 200) == "ok"
  end
end
