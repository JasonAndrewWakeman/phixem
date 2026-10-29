defmodule PhixemWeb.PageLiveTest do
  use PhixemWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    Phixem.Pickem.seed!()
    :ok
  end

  test "home page defaults to the first open week and can select others", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "TOTAL ENTRIES 0"
    assert html =~ "TOTAL POT: 0"
    assert html =~ "Week 8"
    assert html =~ "CAR@GB"
    assert html =~ "CHI@SEA"
    assert html =~ "PERFECT"
    refute html =~ "NE@SEA"

    html = render_click(view, "select_week", %{"number" => "1"})
    assert html =~ "NE@SEA"
    assert html =~ "SEA"
    refute html =~ "CAR@GB"
  end

  test "GET /health still works", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert text_response(conn, 200) == "ok"
  end
end
