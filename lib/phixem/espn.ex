defmodule Phixem.Espn do
  @moduledoc false

  @scoreboard "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"
  @user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  @aliases %{
    "WAS" => "WSH",
    "WSH" => "WSH",
    "JAC" => "JAX",
    "JAX" => "JAX",
    "LA" => "LAR",
    "LAR" => "LAR",
    "GNB" => "GB",
    "GB" => "GB",
    "SFO" => "SF",
    "SF" => "SF",
    "NWE" => "NE",
    "NE" => "NE",
    "NOR" => "NO",
    "NO" => "NO",
    "TAM" => "TB",
    "TB" => "TB",
    "KAN" => "KC",
    "KC" => "KC",
    "ARZ" => "ARI",
    "ARI" => "ARI"
  }

  def fetch_scoreboard(week) do
    url = "#{@scoreboard}?seasontype=2&week=#{week.number}&year=#{season_year(week)}"

    case Req.get(url, headers: [{"user-agent", @user_agent}, {"accept", "application/json"}]) do
      {:ok, %{status: 200, body: body}} -> {:ok, parse_scoreboard(body, week)}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_scoreboard(body, week) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> parse_scoreboard(map, week)
      {:error, _} -> %{winners: %{}, mnf_total: nil}
    end
  end

  def parse_scoreboard(body, week) when is_map(body) do
    allowed = MapSet.new(Phixem.Pickem.Week.matchup_list(week))

    games =
      body
      |> Map.get("events", [])
      |> Enum.map(&parse_event/1)
      |> Enum.reject(&is_nil/1)

    winners =
      games
      |> Enum.filter(& &1.final?)
      |> Enum.map(fn game -> {game.matchup, game.winner} end)
      |> Enum.filter(fn {matchup, winner} ->
        matchup in allowed and (winner == "" or winner in String.split(matchup, "@"))
      end)
      |> Map.new()

    mnf_total =
      games
      |> Enum.filter(&(&1.final? and &1.monday?))
      |> Enum.max_by(& &1.start, DateTime, fn -> nil end)
      |> case do
        nil -> nil
        game -> game.away_score + game.home_score
      end

    %{winners: winners, mnf_total: mnf_total}
  end

  defp season_year(%{starts_on: date}) do
    if date.month < 3, do: date.year - 1, else: date.year
  end

  defp parse_event(event) when is_map(event) do
    competition = event |> Map.get("competitions", []) |> List.first()

    with %{} <- competition,
         %{"competitors" => competitors} <- competition,
         {away, home} <- teams(competitors) do
      away_abbr = alias_abbr(away["team"]["abbreviation"])
      home_abbr = alias_abbr(home["team"]["abbreviation"])
      matchup = "#{away_abbr}@#{home_abbr}"
      away_score = parse_score(away["score"])
      home_score = parse_score(home["score"])
      start = parse_start(event["date"] || competition["date"])

      %{
        matchup: matchup,
        final?: final?(competition),
        monday?: monday?(start),
        start: start || ~U[1970-01-01 00:00:00Z],
        away_score: away_score || 0,
        home_score: home_score || 0,
        winner: winner(away_abbr, home_abbr, away, home, away_score, home_score)
      }
    else
      _ -> nil
    end
  end

  defp parse_event(_), do: nil

  defp teams(competitors) when is_list(competitors) do
    away = Enum.find(competitors, &(Map.get(&1, "homeAway") == "away"))
    home = Enum.find(competitors, &(Map.get(&1, "homeAway") == "home"))
    if away && home, do: {away, home}
  end

  defp teams(_), do: nil

  defp alias_abbr(nil), do: ""

  defp alias_abbr(abbr) do
    abbr = abbr |> to_string() |> String.upcase()
    Map.get(@aliases, abbr, abbr)
  end

  defp parse_score(nil), do: nil
  defp parse_score(score) when is_integer(score), do: score

  defp parse_score(score) when is_binary(score) do
    case Integer.parse(score) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_score(_), do: nil

  defp parse_start(nil), do: nil

  defp parse_start(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.shift_zone!(dt, "Etc/UTC")
      _ -> nil
    end
  end

  defp final?(%{"status" => status}) do
    type = status["type"] || %{}
    type["completed"] == true or type["state"] == "post" or type["name"] == "STATUS_FINAL"
  end

  defp final?(_), do: false

  defp monday?(nil), do: false

  defp monday?(%DateTime{} = utc) do
    eastern = Phixem.Eastern.from_utc(utc)
    Date.day_of_week(DateTime.to_date(eastern)) == 1
  end

  defp winner(away_abbr, home_abbr, away, home, away_score, home_score) do
    cond do
      away["winner"] == true -> away_abbr
      home["winner"] == true -> home_abbr
      is_integer(away_score) and is_integer(home_score) and away_score == home_score -> ""
      is_integer(away_score) and is_integer(home_score) and away_score > home_score -> away_abbr
      is_integer(away_score) and is_integer(home_score) -> home_abbr
      true -> away_abbr
    end
  end
end
