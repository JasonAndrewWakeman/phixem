defmodule PhixemWeb.AdminController do
  use PhixemWeb, :controller

  alias Phixem.Pickem
  alias Phixem.Pickem.Entry

  plug :require_admin when action in [:save_perfect, :save_entry]

  def show(conn, params) do
    if get_session(conn, :broncos_admin) do
      render_dashboard(conn, params)
    else
      render(conn, :login, error: nil)
    end
  end

  def create(conn, params) do
    passphrase = params["passphrase"]

    if Phixem.AdminAuth.valid_passphrase?(passphrase) do
      conn
      |> configure_session(renew: true)
      |> put_session(:broncos_admin, true)
      |> redirect(to: admin_path(params))
    else
      conn
      |> put_status(:unauthorized)
      |> render(:login, error: "Invalid passphrase")
    end
  end

  def save_perfect(conn, params) do
    week_number = params["week"]
    winners = params["winners"] || %{}

    case Pickem.save_perfect_winners(week_number, winners) do
      {:ok, _entry} ->
        conn
        |> put_flash(:info, "PERFECT winners saved for week #{week_number}.")
        |> redirect(to: ~p"/broncosAdmin?week=#{week_number}")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "That week was not found.")
        |> redirect(to: ~p"/broncosAdmin")

      {:error, :invalid_winners} ->
        conn
        |> put_flash(:error, "Each winner must be one of the two teams in that matchup.")
        |> redirect(to: ~p"/broncosAdmin?week=#{week_number}")
    end
  end

  def save_entry(conn, params) do
    week_number = params["week"]

    attrs = %{
      "username" => params["username"],
      "winners" => params["winners"] || %{},
      "tie_breaker" => params["tie_breaker"]
    }

    case Pickem.create_entry(week_number, attrs) do
      {:ok, entry} ->
        conn
        |> put_flash(:info, "Added #{entry.username} to week #{week_number}.")
        |> redirect(to: ~p"/broncosAdmin?week=#{week_number}")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "That week was not found.")
        |> redirect(to: ~p"/broncosAdmin")

      {:error, :invalid_name} ->
        conn
        |> put_flash(:error, "Enter a player name.")
        |> redirect(to: ~p"/broncosAdmin?week=#{week_number}")

      {:error, :reserved_name} ->
        conn
        |> put_flash(:error, "PERFECT is reserved for the winners row.")
        |> redirect(to: ~p"/broncosAdmin?week=#{week_number}")

      {:error, :invalid_winners} ->
        conn
        |> put_flash(:error, "Each pick must be one of the two teams in that matchup.")
        |> redirect(to: ~p"/broncosAdmin?week=#{week_number}")

      {:error, :incomplete_winners} ->
        conn
        |> put_flash(:error, "Select a winner for every matchup.")
        |> redirect(to: ~p"/broncosAdmin?week=#{week_number}")
    end
  end

  defp render_dashboard(conn, params) do
    weeks = Pickem.list_weeks()
    week = Pickem.get_week(params["week"]) || Pickem.get_week(Pickem.default_week_number())
    winners = week && perfect_winners(week)

    render(conn, :unlocked,
      weeks: weeks,
      week: week,
      winners: winners || %{}
    )
  end

  defp perfect_winners(week) do
    week.entries
    |> Enum.find(&(&1.username == "PERFECT"))
    |> then(fn
      nil -> %{}
      entry -> Entry.pick_map(entry)
    end)
  end

  defp admin_path(%{"week" => week}) when is_binary(week) and week != "",
    do: ~p"/broncosAdmin?week=#{week}"

  defp admin_path(_), do: ~p"/broncosAdmin"

  defp require_admin(conn, _opts) do
    if get_session(conn, :broncos_admin) do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> render(:login, error: nil)
      |> halt()
    end
  end
end
