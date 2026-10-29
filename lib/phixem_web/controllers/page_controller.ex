defmodule PhixemWeb.PageController do
  use PhixemWeb, :controller

  def home(conn, _params) do
    page_loads = Phixem.Visits.record_and_list()
    render(conn, :home, page_loads: page_loads)
  end

  def health(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end
end
