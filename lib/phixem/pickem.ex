defmodule Phixem.Pickem do
  @moduledoc """
  Weekly NFL pick boards: frozen matchup headers, a winners row, then entries.
  """

  import Ecto.Query

  alias Phixem.Repo
  alias Phixem.Pickem.{Entry, Week}

  @entry_coins 8.5
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

  def default_week_number(now \\ DateTime.utc_now()) do
    weeks = list_weeks()

    case weeks do
      [] ->
        nil

      weeks ->
        sunday = Phixem.Eastern.pickem_sunday(now)

        cond do
          week = Enum.find(weeks, &(&1.starts_on == sunday)) ->
            week.number

          Date.compare(sunday, hd(weeks).starts_on) == :lt ->
            hd(weeks).number

          true ->
            weeks
            |> Enum.filter(&(Date.compare(&1.starts_on, sunday) != :gt))
            |> List.last()
            |> then(fn
              nil -> List.last(weeks).number
              week -> week.number
            end)
        end
    end
  end

  def empty? do
    Repo.aggregate(Week, :count) == 0
  end

  def highlight_roles(%Week{entries: entries} = week) when is_list(entries) do
    perfect = Enum.find(entries, & &1.winners_row)
    players = Enum.reject(entries, & &1.winners_row)
    actual = actual_tie_breaker(week, perfect)

    cond do
      not is_integer(actual) or players == [] ->
        %{}

      true ->
        max_correct = players |> Enum.map(&(&1.correct_choices || 0)) |> Enum.max()
        leaders = Enum.filter(players, &((&1.correct_choices || 0) == max_correct))

        first_ids =
          if length(leaders) == 1 do
            MapSet.new([hd(leaders).id])
          else
            leaders
            |> Enum.map(&{&1, &1.correct_choices || 0})
            |> closest_tiebreakers(actual)
            |> MapSet.new(& &1.id)
          end

        Map.new(leaders, fn player ->
          role = if MapSet.member?(first_ids, player.id), do: :first, else: :silver
          {player.id, role}
        end)
    end
  end

  def highlight_roles(_), do: %{}

  def tie_breaker_ready?(%Week{} = week) do
    perfect =
      case week.entries do
        entries when is_list(entries) -> Enum.find(entries, & &1.winners_row)
        _ -> perfect_entry(week)
      end

    is_integer(actual_tie_breaker(week, perfect))
  end

  def week_results_final?(%Week{} = week) do
    week = get_week(week.number) || week
    matchups = Week.matchup_list(week)
    perfect = Enum.find(week.entries, & &1.winners_row)
    picks = perfect_picks(perfect)

    filled =
      Enum.all?(matchups, fn matchup ->
        team = Map.get(picks, matchup, "")
        is_binary(team) and team != ""
      end)

    filled and tie_breaker_ready?(week)
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

  def save_perfect_winners(week_number, winners, tie_breaker \\ nil)

  def save_perfect_winners(week_number, winners, tie_breaker) when is_map(winners) do
    case get_week(week_number) do
      nil ->
        {:error, :not_found}

      week ->
        with :ok <- validate_winners(week, winners),
             {:ok, parsed_tb} <- parse_optional_tie_breaker(tie_breaker) do
          persist_perfect(week, winners, parsed_tb)
        end
    end
  end

  def save_perfect_winners(_, _, _), do: {:error, :invalid}

  def create_entry(week_number, attrs) when is_map(attrs) do
    case get_week(week_number) do
      nil ->
        {:error, :not_found}

      %{entries_locked: true} ->
        {:error, :week_locked}

      week ->
        username = attrs |> Map.get("username", "") |> normalize_username()
        winners = Map.get(attrs, "winners") || Map.get(attrs, :winners) || %{}
        tie_breaker = attrs |> Map.get("tie_breaker", Map.get(attrs, :tie_breaker, "")) |> to_string() |> String.trim()

        missing = missing_entry_fields(week, username, winners, tie_breaker)

        cond do
          String.downcase(username) == "perfect" ->
            {:error, :reserved_name}

          missing != [] ->
            {:error, {:missing_fields, missing}}

          duplicate_username?(week, username) ->
            {:error, {:duplicate_name, username}}

          true ->
            with :ok <- validate_winners(week, winners) do
              persist_entry(week, username, winners, tie_breaker)
            end
        end
    end
  end

  def create_entry(_, _), do: {:error, :invalid}

  def lock_week(week_number) do
    case get_week(week_number) do
      nil ->
        {:error, :not_found}

      %{entries_locked: true} ->
        {:error, :already_locked}

      week ->
        week
        |> Week.changeset(%{entries_locked: true})
        |> Repo.update()
        |> case do
          {:ok, locked} ->
            Phoenix.PubSub.broadcast(Phixem.PubSub, "pickem", {:week_updated, locked.number})
            {:ok, locked}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp upsert_week!(data) do
    existing = Repo.get_by(Week, number: data["number"])
    json_tb = stored_tie_breaker_value(data)
    json_mnf = stored_mnf_score(data)

    attrs = %{
      number: data["number"],
      tab: "stored",
      title: "Week #{data["number"]}",
      starts_on: Date.from_iso8601!(data["starts_on"]),
      matchups: Enum.join(data["matchups"] || [], ","),
      complete: data["complete"] == true,
      mnf_score: json_mnf || (existing && existing.mnf_score),
      tie_breaker_value: json_tb || (existing && existing.tie_breaker_value)
    }

    week =
      case existing do
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
      changeset =
        %Entry{}
        |> Entry.changeset(%{
          week_id: week.id,
          username: username,
          winners_row: false,
          picks: picks,
          tie_breaker: tie_breaker
        })

      case Repo.insert(changeset) do
        {:ok, entry} ->
          sync_perfect_coins!(week)
          recalculate_standings!(week)
          Phoenix.PubSub.broadcast(Phixem.PubSub, "pickem", {:week_updated, week.number})
          Repo.get!(Entry, entry.id)

        {:error, _changeset} ->
          Repo.rollback({:duplicate_name, username})
      end
    end)
    |> case do
      {:ok, entry} -> {:ok, entry}
      {:error, {:duplicate_name, name}} -> {:error, {:duplicate_name, name}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_username(name) do
    name
    |> to_string()
    |> String.trim()
    |> String.replace(~r/\s+/u, " ")
  end

  defp duplicate_username?(week, username) do
    key = String.downcase(username)

    Repo.exists?(
      from e in Entry,
        where: e.week_id == ^week.id and fragment("lower(?)", e.username) == ^key
    )
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

  defp persist_perfect(week, winners, parsed_tb) do
    existing = perfect_entry(week)
    merged = Map.merge(perfect_picks(existing), stringify_winner_map(winners))
    picks = Jason.encode!(merged)

    attrs = %{
      week_id: week.id,
      username: "PERFECT",
      winners_row: true,
      picks: picks
    }

    attrs =
      if is_integer(parsed_tb) do
        Map.put(attrs, :tie_breaker, Integer.to_string(parsed_tb))
      else
        attrs
      end

    Repo.transaction(fn ->
      week =
        if is_integer(parsed_tb) do
          week
          |> Week.changeset(%{
            mnf_score: Integer.to_string(parsed_tb),
            tie_breaker_value: parsed_tb
          })
          |> Repo.update!()
        else
          week
        end

      entry =
        case existing do
          nil ->
            %Entry{}
            |> Entry.changeset(attrs)
            |> Repo.insert!()

          entry ->
            entry
            |> Entry.changeset(attrs)
            |> Repo.update!()
        end

      recalculate_standings!(week)
      Phoenix.PubSub.broadcast(Phixem.PubSub, "pickem", {:perfect_updated, week.number})
      Repo.get!(Entry, entry.id)
    end)
  end

  defp parse_optional_tie_breaker(value) when value in [nil, ""], do: {:ok, nil}

  defp parse_optional_tie_breaker(value) do
    case score_total(value) do
      total when is_integer(total) -> {:ok, total}
      _ -> {:error, :invalid_tie_breaker}
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

    ready = is_integer(actual_tie_breaker(week, perfect))
    payouts = if ready, do: payouts(week, perfect, scored_matchups, scored_players), else: %{}

    if perfect do
      perfect
      |> Entry.changeset(%{correct_choices: length(scored_matchups)})
      |> Repo.update!()
    end

    Enum.each(scored_players, fn {player, correct} ->
      player
      |> Entry.changeset(%{
        correct_choices: correct,
        coins_won: if(ready, do: Map.get(payouts, player.id, 0), else: nil)
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
          {away, home} -> to_string(team) in [away, home, "", "TIE"]
          _ -> false
        end
      end)

    if invalid == [] do
      :ok
    else
      {:error, :invalid_winners}
    end
  end

  defp missing_entry_fields(week, username, winners, tie_breaker) do
    picks = stringify_winner_map(winners)

    matchups =
      Enum.reject(Week.matchup_list(week), fn matchup ->
        team = Map.get(picks, matchup, "")
        is_binary(team) and team != ""
      end)

    name = if username == "", do: ["Name"], else: []
    tb = if tie_breaker == "", do: ["Tie-breaker"], else: []
    name ++ matchups ++ tb
  end

  defp stringify_winner_map(winners) do
    Map.new(winners, fn {matchup, team} ->
      team = to_string(team)
      {to_string(matchup), if(team in ["", "TIE"], do: "", else: team)}
    end)
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
    halves = round(total * 2)
    base = div(halves, count)
    extra = rem(halves, count)

    players
    |> Enum.with_index()
    |> Map.new(fn {player, index} ->
      {player.id, (base + if(index < extra, do: 1, else: 0)) / 2}
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
