defmodule PhixemWeb.PageLiveTest do
  use PhixemWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    Phixem.Pickem.seed!()
    :ok
  end

  test "upcoming week shows PERFECT winners and seed entries", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Upcoming week"
    assert html =~ "CAR@GB"
    assert html =~ "CHI@SEA"
    assert html =~ "PERFECT"
    assert html =~ "morpheus"
    assert html =~ "Big Daddy"
    assert html =~ "Neo"
    assert render(view) =~ "GB"
  end

  test "last week tab shows completed winners without player seed rows", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = render_click(view, "select_tab", %{"tab" => "last_week"})

    assert html =~ "NE@CHI"
    assert html =~ "DAL@PHI"
    assert html =~ "38-21"
    refute html =~ "morpheus"
  end

  test "GET /health still works", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert text_response(conn, 200) == "ok"
  end
end
