defmodule Phixem.Pickem do
  @moduledoc """
  Weekly NFL pick boards: frozen matchup headers, a winners row, then entries.
  """

  import Ecto.Query

  alias Phixem.Repo
  alias Phixem.Pickem.{Entry, Week}

  def get_week_by_tab(tab) when is_binary(tab) do
    Week
    |> Repo.get_by(tab: tab)
    |> Repo.preload(entries: from(e in Entry, order_by: [desc: e.winners_row, desc: e.correct_choices, asc: e.username]))
  end

  def empty? do
    Repo.aggregate(Week, :count) == 0
  end

  def seed_if_empty! do
    if empty?() do
      seed!()
    else
      :ok
    end
  end

  def seed! do
    Repo.delete_all(Entry)
    Repo.delete_all(Week)

    last = insert_week!(last_week_attrs())
    upcoming = insert_week!(upcoming_week_attrs())

    Enum.each(last_week_entries(), &insert_entry!(last, &1))
    Enum.each(upcoming_week_entries(), &insert_entry!(upcoming, &1))

    :ok
  end

  defp insert_week!(attrs) do
    %Week{}
    |> Week.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_entry!(week, attrs) do
    picks = Jason.encode!(attrs.picks)

    %Entry{}
    |> Entry.changeset(Map.merge(attrs, %{week_id: week.id, picks: picks}))
    |> Repo.insert!()
  end

  defp last_week_attrs do
    %{
      number: 7,
      tab: "last_week",
      title: "Last week",
      complete: true,
      mnf_score: "38-21",
      tie_breaker_value: 59,
      matchups:
        Enum.join(
          [
            "NE@CHI",
            "PIT@NO",
            "SF@ATL",
            "CLE@TEN",
            "IND@MIN",
            "MIA@NYJ",
            "TB@CAR",
            "CIN@BAL",
            "NYG@HOU",
            "DEN@ARI",
            "GB@DET",
            "LAR@LV",
            "KC@SEA",
            "DAL@PHI"
          ],
          ","
        )
    }
  end

  defp upcoming_week_attrs do
    %{
      number: 8,
      tab: "upcoming",
      title: "Upcoming week",
      complete: false,
      mnf_score: nil,
      tie_breaker_value: nil,
      matchups:
        Enum.join(
          [
            "CAR@GB",
            "BAL@BUF",
            "TEN@CIN",
            "ARI@DAL",
            "MIN@DET",
            "LV@NYJ",
            "CLE@PIT",
            "ATL@TB",
            "IND@JAX",
            "LAC@LAR",
            "KC@DEN",
            "NE@MIA",
            "PHI@WSH",
            "CHI@SEA"
          ],
          ","
        )
    }
  end

  defp last_week_entries do
    matchups = String.split(last_week_attrs().matchups, ",", trim: true)

    winners = [
      "CHI",
      "PIT",
      "ATL",
      "CLE",
      "MIN",
      "MIA",
      "TB",
      "CIN",
      "NYG",
      "DEN",
      "DET",
      "LAR",
      "SEA",
      "DAL"
    ]

    [
      %{
        username: "PERFECT",
        winners_row: true,
        picks: Map.new(Enum.zip(matchups, winners)),
        tie_breaker: "38-21",
        correct_choices: nil,
        coins_won: nil,
        total_coins_won: nil
      }
    ]
  end

  defp upcoming_week_entries do
    matchups = String.split(upcoming_week_attrs().matchups, ",", trim: true)

    perfect = ["GB", "BUF", "CIN", "ARI", "DET", "NYJ", "CLE", "TB", "IND", "LAC", "KC", "NE", "PHI", "SEA"]
    morpheus = ["GB", "BUF", "CIN", "ARI", "DET", "LV", "PIT", "ATL", "JAX", "LAR", "DEN", "NE", "PHI", "SEA"]
    big_daddy = ["GB", "BUF", "CIN", "DAL", "MIN", "NYJ", "CLE", "ATL", "JAX", "LAR", "DEN", "NE", "WSH", "SEA"]
    neo = ["GB", "BUF", "CIN", "ARI", "MIN", "NYJ", "CLE", "ATL", "IND", "LAR", "DEN", "NE", "PHI", "SEA"]

    [
      %{
        username: "PERFECT",
        winners_row: true,
        picks: Map.new(Enum.zip(matchups, perfect)),
        tie_breaker: "34",
        correct_choices: nil,
        coins_won: nil,
        total_coins_won: nil
      },
      %{
        username: "morpheus",
        winners_row: false,
        picks: Map.new(Enum.zip(matchups, morpheus)),
        tie_breaker: nil,
        correct_choices: nil,
        coins_won: nil,
        total_coins_won: nil
      },
      %{
        username: "Big Daddy",
        winners_row: false,
        picks: Map.new(Enum.zip(matchups, big_daddy)),
        tie_breaker: nil,
        correct_choices: nil,
        coins_won: nil,
        total_coins_won: nil
      },
      %{
        username: "Neo",
        winners_row: false,
        picks: Map.new(Enum.zip(matchups, neo)),
        tie_breaker: nil,
        correct_choices: nil,
        coins_won: nil,
        total_coins_won: nil
      }
    ]
  end
end
