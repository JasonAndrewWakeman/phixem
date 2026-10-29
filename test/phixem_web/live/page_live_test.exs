defmodule PhixemWeb.PageLiveTest do
  use PhixemWeb.ConnCase

  import Phoenix.LiveViewTest

  test "connected mount records a page load", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert render(view) =~ "1 load(s) recorded"
    assert render(view) =~ "latest"
  end

  test "a second LiveView updates the first without a full page reload", %{conn: conn} do
    {:ok, view1, _html} = live(conn, ~p"/")
    assert render(view1) =~ "1 load(s) recorded"

    {:ok, view2, _html} = live(build_conn(), ~p"/")
    assert render(view2) =~ "2 load(s) recorded"
    assert render(view1) =~ "2 load(s) recorded"
  end

  test "GET /health does not record a page load", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert text_response(conn, 200) == "ok"

    {:ok, view, _html} = live(build_conn(), ~p"/")
    assert render(view) =~ "1 load(s) recorded"
  end
end
