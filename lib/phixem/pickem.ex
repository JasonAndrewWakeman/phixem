defmodule Phixem.Pickem do
  @moduledoc """
  Weekly NFL pick boards: frozen matchup headers, a winners row, then entries.
  """

  import Ecto.Query

  alias Phixem.Repo
  alias Phixem.Pickem.{Entry, Week}

  @entry_coins 9
  @tie_free_entry 10

  def entry_coins, do: @entry_coins

  def list_weeks do
    Week
    |> order_by([w], asc: w.number)
    |> Repo.all()
  end

  def get_week(number) when is_integer(number) do
    Week
    |> Repo.get_by(number: number)
    |> preload_entries()
  end

  def get_week(number) when is_binary(number) do
    case Integer.parse(number) do
      {int, ""} -> get_week(int)
      _ -> nil
    end
  end

  def get_week(_), do: nil

  def default_week_number do
    weeks = list_weeks()

    cond do
      weeks == [] -> nil
      week = Enum.find(weeks, &(&1.complete == false)) -> week.number
      true -> List.last(weeks).number
    end
  end

  def empty? do
    Repo.aggregate(Week, :count) == 0
  end

  def seed_if_empty! do
    seed_season!()
  end

  def seed! do
    Repo.delete_all(Entry)
    Repo.delete_all(Week)
    seed_season!()
  end

  def seed_season! do
    Enum.each(season_weeks(), &upsert_week!/1)
    :ok
  end

  def save_perfect_winners(week_number, winners) when is_map(winners) do
    case get_week(week_number) do
      nil ->
        {:error, :not_found}

      week ->
        with :ok <- validate_winners(week, winners) do
          persist_perfect(week, winners)
        end
    end
  end

  def save_perfect_winners(_, _), do: {:error, :invalid}

  def create_entry(week_number, attrs) when is_map(attrs) do
    case get_week(week_number) do
      nil ->
        {:error, :not_found}

      week ->
        username = attrs |> Map.get("username", "") |> to_string() |> String.trim()
        winners = Map.get(attrs, "winners") || Map.get(attrs, :winners) || %{}
        tie_breaker = attrs |> Map.get("tie_breaker", Map.get(attrs, :tie_breaker, "")) |> to_string() |> String.trim()

        cond do
          username == "" ->
            {:error, :invalid_name}

          String.downcase(username) == "perfect" ->
            {:error, :reserved_name}

          true ->
            with :ok <- validate_complete_winners(week, winners) do
              persist_entry(week, username, winners, tie_breaker)
            end
        end
    end
  end

  def create_entry(_, _), do: {:error, :invalid}

  defp upsert_week!(data) do
    attrs = %{
      number: data["number"],
      tab: "stored",
      title: "Week #{data["number"]}",
      starts_on: Date.from_iso8601!(data["starts_on"]),
      matchups: Enum.join(data["matchups"] || [], ","),
      complete: data["complete"] == true,
      mnf_score: stored_mnf_score(data),
      tie_breaker_value: stored_tie_breaker_value(data)
    }

    week =
      case Repo.get_by(Week, number: attrs.number) do
        nil ->
          %Week{}
          |> Week.changeset(attrs)
          |> Repo.insert!()

        week ->
          week
          |> Week.changeset(attrs)
          |> Repo.update!()
      end

    upsert_perfect!(week, data)
    week
  end

  defp persist_entry(week, username, winners, tie_breaker) do
    picks = winners |> stringify_winner_map() |> Jason.encode!()

    Repo.transaction(fn ->
      entry =
        %Entry{}
        |> Entry.changeset(%{
          week_id: week.id,
          username: username,
          winners_row: false,
          picks: picks,
          tie_breaker: tie_breaker
        })
        |> Repo.insert!()

      sync_perfect_coins!(week)
      recalculate_standings!(week)

      Phoenix.PubSub.broadcast(Phixem.PubSub, "pickem", {:week_updated, week.number})
      Repo.get!(Entry, entry.id)
    end)
  end

  defp sync_perfect_coins!(week) do
    count =
      Repo.aggregate(
        from(e in Entry, where: e.week_id == ^week.id and e.winners_row == false),
        :count
      )

    coins = count * @entry_coins

    case perfect_entry(week) do
      nil ->
        :ok

      entry ->
        entry
        |> Entry.changeset(%{coins_won: coins})
        |> Repo.update!()
    end
  end

  defp persist_perfect(week, winners) do
    existing = perfect_entry(week)
    merged = Map.merge(perfect_picks(existing), stringify_winner_map(winners))
    picks = Jason.encode!(merged)

    attrs = %{
      week_id: week.id,
      username: "PERFECT",
      winners_row: true,
      picks: picks
    }

    result =
      case existing do
        nil ->
          %Entry{}
          |> Entry.changeset(attrs)
          |> Repo.insert()

        entry ->
          entry
          |> Entry.changeset(attrs)
          |> Repo.update()
      end

    with {:ok, entry} <- result do
      recalculate_standings!(week)
      Phoenix.PubSub.broadcast(Phixem.PubSub, "pickem", {:perfect_updated, week.number})
      {:ok, Repo.get!(Entry, entry.id)}
    end
  end

  def recalculate_standings!(week) do
    week = Repo.get!(Week, week.id)
    entries = Repo.all(from e in Entry, where: e.week_id == ^week.id)
    perfect = Enum.find(entries, & &1.winners_row)
    players = Enum.reject(entries, & &1.winners_row)
    perfect_picks = perfect_picks(perfect)

    scored_matchups =
      Enum.filter(Week.matchup_list(week), fn matchup ->
        winner = perfect_picks[matchup]
        is_binary(winner) and winner != ""
      end)

    scored_players =
      Enum.map(players, fn player ->
        picks = Entry.pick_map(player)
        correct = Enum.count(scored_matchups, fn matchup -> picks[matchup] == perfect_picks[matchup] end)
        {player, correct}
      end)

    payouts = payouts(week, perfect, scored_matchups, scored_players)

    if perfect do
      perfect
      |> Entry.changeset(%{correct_choices: length(scored_matchups)})
      |> Repo.update!()
    end

    Enum.each(scored_players, fn {player, correct} ->
      player
      |> Entry.changeset(%{
        correct_choices: correct,
        coins_won: Map.get(payouts, player.id, 0)
      })
      |> Repo.update!()
    end)

    :ok
  end

  defp validate_winners(week, winners) do
    allowed =
      Map.new(Week.matchup_list(week), fn matchup ->
        {matchup, Week.matchup_teams(matchup)}
      end)

    invalid =
      Enum.reject(winners, fn {matchup, team} ->
        case allowed[to_string(matchup)] do
          {away, home} -> team in [away, home]
          _ -> false
        end
      end)

    if invalid == [] do
      :ok
    else
      {:error, :invalid_winners}
    end
  end

  defp validate_complete_winners(week, winners) do
    with :ok <- validate_winners(week, winners) do
      submitted = winners |> stringify_winner_map() |> Map.keys()
      missing = Week.matchup_list(week) -- submitted

      if missing == [] do
        :ok
      else
        {:error, :incomplete_winners}
      end
    end
  end

  defp stringify_winner_map(winners) do
    Map.new(winners, fn {matchup, team} -> {to_string(matchup), to_string(team)} end)
  end

  defp perfect_entry(%Week{id: id}) do
    Repo.get_by(Entry, week_id: id, username: "PERFECT")
  end

  defp perfect_picks(nil), do: %{}
  defp perfect_picks(entry), do: Entry.pick_map(entry)

  defp upsert_perfect!(week, data) do
    case Repo.get_by(Entry, week_id: week.id, username: "PERFECT") do
      nil ->
        winners = seeded_perfect_winners(data)
        decided = Enum.count(winners, fn {_matchup, team} -> is_binary(team) and team != "" end)

        %Entry{}
        |> Entry.changeset(%{
          week_id: week.id,
          username: "PERFECT",
          winners_row: true,
          picks: Jason.encode!(winners),
          tie_breaker: stored_mnf_score(data),
          correct_choices: decided,
          coins_won: 0
        })
        |> Repo.insert!()

      _entry ->
        :ok
    end
  end

  defp seeded_perfect_winners(%{"complete" => true} = data), do: data["winners"] || %{}
  defp seeded_perfect_winners(_data), do: %{}

  defp stored_tie_breaker_value(data) do
    cond do
      is_integer(data["tie_breaker_value"]) -> data["tie_breaker_value"]
      total = score_total(data["mnf_score"]) -> total
      true -> nil
    end
  end

  defp stored_mnf_score(data) do
    case stored_tie_breaker_value(data) do
      total when is_integer(total) -> Integer.to_string(total)
      _ -> nil
    end
  end

  defp season_weeks do
    season_path()
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("weeks")
  end

  defp season_path do
    Path.join(:code.priv_dir(:phixem), "nfl/2026_regular_season.json")
  end

  defp preload_entries(nil), do: nil

  defp preload_entries(week) do
    week = Repo.preload(week, :entries)
    %{week | entries: sort_entries(week.entries, week)}
  end

  defp sort_entries(entries, week) do
    perfect = Enum.find(entries, & &1.winners_row)
    actual_tb = actual_tie_breaker(week, perfect)

    Enum.sort_by(entries, fn entry ->
      distance = tie_breaker_distance(entry, actual_tb)

      {
        if(entry.winners_row, do: 0, else: 1),
        -(entry.correct_choices || -1),
        if(is_nil(distance), do: 1, else: 0),
        distance || 0,
        String.downcase(entry.username || "")
      }
    end)
  end

  defp payouts(_week, _perfect, [], scored_players) do
    Map.new(scored_players, fn {player, _correct} -> {player.id, 0} end)
  end

  defp payouts(_week, _perfect, _scored_matchups, []) do
    %{}
  end

  defp payouts(week, perfect, _scored_matchups, scored_players) do
    pot = length(scored_players) * @entry_coins
    max_correct = scored_players |> Enum.map(&elem(&1, 1)) |> Enum.max()
    leaders = Enum.filter(scored_players, fn {_player, correct} -> correct == max_correct end)
    leader_ids = MapSet.new(Enum.map(leaders, fn {player, _} -> player.id end))

    remainder_shares =
      if length(leaders) == 1 do
        [{winner, _}] = leaders
        %{winner.id => pot}
      else
        remainder = max(pot - @tie_free_entry * length(leaders), 0)
        closest = closest_tiebreakers(leaders, actual_tie_breaker(week, perfect))
        split_coins(closest, remainder)
      end

    Map.new(scored_players, fn {player, _correct} ->
      base = if MapSet.member?(leader_ids, player.id) and length(leaders) > 1, do: @tie_free_entry, else: 0
      {player.id, base + Map.get(remainder_shares, player.id, 0)}
    end)
  end

  defp closest_tiebreakers(_leaders, nil), do: []

  defp closest_tiebreakers(leaders, actual) do
    distances =
      leaders
      |> Enum.map(fn {player, _} -> {player, score_total(player.tie_breaker)} end)
      |> Enum.filter(fn {_player, total} -> is_integer(total) end)
      |> Enum.map(fn {player, total} -> {player, abs(total - actual)} end)

    case distances do
      [] ->
        []

      list ->
        best = list |> Enum.map(&elem(&1, 1)) |> Enum.min()

        list
        |> Enum.filter(fn {_player, distance} -> distance == best end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort_by(&String.downcase(&1.username))
    end
  end

  defp split_coins([], _total), do: %{}
  defp split_coins(_players, total) when total <= 0, do: %{}

  defp split_coins(players, total) do
    count = length(players)
    base = div(total, count)
    extra = rem(total, count)

    players
    |> Enum.with_index()
    |> Map.new(fn {player, index} ->
      {player.id, base + if(index < extra, do: 1, else: 0)}
    end)
  end

  defp actual_tie_breaker(week, perfect) do
    cond do
      is_integer(week.tie_breaker_value) -> week.tie_breaker_value
      total = score_total(week.mnf_score) -> total
      true -> score_total(perfect && perfect.tie_breaker)
    end
  end

  defp tie_breaker_distance(%{winners_row: true}, _actual), do: nil

  defp tie_breaker_distance(entry, actual) do
    total = score_total(entry.tie_breaker)

    if is_integer(total) and is_integer(actual) do
      abs(total - actual)
    end
  end

  defp score_total(nil), do: nil
  defp score_total(value) when is_integer(value), do: value

  defp score_total(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        nil

      match?({_int, ""}, Integer.parse(trimmed)) ->
        {int, ""} = Integer.parse(trimmed)
        int

      true ->
        parts =
          trimmed
          |> String.split(~r/[-–]/, trim: true)
          |> Enum.map(&String.trim/1)

        ints =
          Enum.map(parts, fn part ->
            case Integer.parse(part) do
              {int, ""} -> int
              _ -> nil
            end
          end)

        if parts != [] and Enum.all?(ints, &is_integer/1) do
          Enum.sum(ints)
        end
    end
  end

  defp score_total(_), do: nil
end
