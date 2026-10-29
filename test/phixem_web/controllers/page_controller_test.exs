defmodule PhixemWeb.PageControllerTest do
  use PhixemWeb.ConnCase

  test "GET / records a page load and lists timestamps", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "this request"
    assert html_response(conn, 200) =~ "1 load(s) recorded"

    conn = get(recycle(conn), ~p"/")
    assert html_response(conn, 200) =~ "2 load(s) recorded"
  end

  test "GET /health does not record a page load", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert text_response(conn, 200) == "ok"

    conn = get(recycle(conn), ~p"/")
    assert html_response(conn, 200) =~ "1 load(s) recorded"
  end
end
