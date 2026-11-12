defmodule Phixem.ScoreSync do
  @moduledoc false

  require Logger

  alias Phixem.Pickem
  alias Phixem.Pickem.Entry

  def sync_current_week(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    number = Pickem.default_week_number(now)

    case number && Pickem.get_week(number) do
      nil -> {:ok, :no_week}
      week -> sync_week(week, opts)
    end
  end

  def sync_week(week, opts \\ []) do
    week = Pickem.get_week(week.number) || week

    if Pickem.week_results_final?(week) do
      {:ok, :already_final}
    else
      fetch = Keyword.get(opts, :fetch, &Phixem.Espn.fetch_scoreboard/1)

      case fetch.(week) do
        {:ok, %{winners: winners, mnf_total: mnf_total}} ->
          apply_results(week, winners, mnf_total)

        {:ok, parsed} when is_map(parsed) ->
          apply_results(week, Map.get(parsed, :winners, %{}), Map.get(parsed, :mnf_total))

        {:error, reason} ->
          Logger.warning("espn scoreboard fetch failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp apply_results(week, api_winners, mnf_total) do
    week = Pickem.get_week(week.number)
    perfect = Enum.find(week.entries, & &1.winners_row)
    existing = Entry.pick_map(perfect)

    blanks =
      api_winners
      |> Enum.filter(fn {matchup, _winner} ->
        existing |> Map.get(matchup, "") |> to_string() |> String.trim() == ""
      end)
      |> Map.new()

    tb =
      if Pickem.tie_breaker_ready?(week) do
        nil
      else
        mnf_total && Integer.to_string(mnf_total)
      end

    if blanks == %{} and is_nil(tb) do
      {:ok, :no_updates}
    else
      Pickem.save_perfect_winners(week.number, blanks, tb)
    end
  end
end
