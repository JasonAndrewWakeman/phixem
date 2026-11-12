defmodule PhixemWeb.PageLive do
  use PhixemWeb, :live_view

  alias Phixem.Pickem
  alias Phixem.Pickem.{Entry, Week}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Phixem.PubSub, "pickem")
    end

    {:ok,
     socket
     |> assign(:weeks, Pickem.list_weeks())
     |> assign(:search_query, "")
     |> assign(:search_ids, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    week = Pickem.get_week(params["week"]) || Pickem.get_week(Pickem.default_week_number())
    {:noreply, assign_week(socket, week)}
  end

  @impl true
  def handle_event("select_week", %{"number" => number}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?week=#{number}")}
  end

  def handle_event("search_entries", params, socket) do
    query = params["q"] || params["value"] || ""

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> apply_search()
     |> scroll_to_match()}
  end

  @impl true
  def handle_info({msg, number}, socket) when msg in [:perfect_updated, :week_updated] do
    if socket.assigns.week_number == number do
      {:noreply, assign_week(socket, Pickem.get_week(number))}
    else
      {:noreply, socket}
    end
  end

  defp assign_week(socket, nil) do
    socket
    |> assign(:week_number, nil)
    |> assign(:week, nil)
    |> assign(:matchups, [])
    |> assign(:entries, [])
    |> assign(:highlights, %{})
    |> apply_search()
  end

  defp assign_week(socket, week) do
    socket
    |> assign(:week_number, week.number)
    |> assign(:week, week)
    |> assign(:matchups, Week.matchup_list(week))
    |> assign(:entries, week.entries)
    |> assign(:highlights, Pickem.highlight_roles(week))
    |> apply_search()
  end

  defp apply_search(socket) do
    query = socket.assigns[:search_query] || ""
    needle = query |> String.trim() |> String.downcase()
    entries = socket.assigns[:entries] || []

    ids =
      if String.length(needle) < 2 do
        []
      else
        entries
        |> Enum.filter(fn entry ->
          entry.username |> to_string() |> String.downcase() |> String.contains?(needle)
        end)
        |> Enum.map(& &1.id)
      end

    assign(socket, :search_ids, ids)
  end

  defp scroll_to_match(socket) do
    case socket.assigns.search_ids do
      [id | _] -> push_event(socket, "scroll_into_view", %{id: "entry-#{id}"})
      _ -> socket
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>
      Phixem
      <span class="header-stats">
        ENTRIES: <span class="header-stat-value">{player_count(@entries)}</span>
        || TOTAL POT: <span class="header-stat-value">{pot(@entries)}</span>
      </span>
    </h1>
    <p :if={@week && @week.entries_locked} class="week-locked-banner">
      Week locked! the current entries and total pot are final for week {@week.number}
    </p>
    <p :if={!(@week && @week.entries_locked)} class="muted">
      PERFECT is updated as results come in.
      The list sorts based on # correct, if there is a tie, all players with the same number of correct at least win a free entry next week, and the person closest to the tie breaker total score for MNF wins the remainder of the total pot.
      If multiple players are equally close or exact to the tie-breaker the pot is split equally.
    </p>

    <div class="tabs" role="tablist">
      <button
        :for={week <- @weeks}
        type="button"
        role="tab"
        class={if @week_number == week.number, do: "tab on", else: "tab"}
        phx-click="select_week"
        phx-value-number={week.number}
      >
        Week {week.number}
      </button>
    </div>

    <p :if={@week} class="muted">Sunday {@week.starts_on}</p>
    <p :if={is_nil(@week)} class="muted">No week selected.</p>

    <form :if={@week} id="entry-search" class="entry-search" phx-change="search_entries" phx-submit="search_entries">
      <input
        type="search"
        name="q"
        value={@search_query}
        placeholder="search entry by name"
        autocomplete="off"
        phx-debounce="150"
      />
    </form>

    <div :if={@week} class="board">
      <table>
        <thead>
          <tr>
            <th>name</th>
            <th :for={matchup <- @matchups}>{matchup}</th>
            <th>Tie-breaker</th>
            <th># correct</th>
            <th>Coins Won</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={entry <- @entries}
            id={"entry-#{entry.id}"}
            class={entry_row_class(entry, @highlights, @search_ids)}
          >
            <th>{entry.username}</th>
            <td :for={matchup <- @matchups}>{pick(entry, matchup)}</td>
            <td>{tie_breaker_cell(@week, entry)}</td>
            <td>{correct_cell(entry)}</td>
            <td>{coins_cell(@week, entry)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp entry_row_class(entry, highlights, search_ids) do
    place =
      cond do
        entry.winners_row -> "winners"
        Map.get(highlights, entry.id) == :first -> "place-first"
        Map.get(highlights, entry.id) == :silver -> "place-silver"
        true -> nil
      end

    hit = entry.id in search_ids && "search-hit"
    [place, hit]
  end

  defp player_count(entries) do
    Enum.count(entries, &(&1.winners_row == false))
  end

  defp pot(entries) do
    case Enum.find(entries, & &1.winners_row) do
      %{coins_won: coins} when is_number(coins) -> format_coins(coins)
      _ -> 0
    end
  end

  defp pick(entry, matchup) do
    entry |> Entry.pick_map() |> Map.get(matchup, "")
  end

  defp correct_cell(%{winners_row: true} = entry) do
    entry
    |> Entry.pick_map()
    |> Enum.count(fn {_matchup, team} -> is_binary(team) and team != "" end)
  end

  defp correct_cell(entry), do: blank(entry.correct_choices)

  defp blank(nil), do: ""
  defp blank(value), do: value

  defp tie_breaker_cell(week, %{winners_row: true} = entry) do
    cond do
      is_integer(week.tie_breaker_value) -> week.tie_breaker_value
      is_binary(week.mnf_score) and week.mnf_score != "" -> week.mnf_score
      is_binary(entry.tie_breaker) -> entry.tie_breaker
      true -> ""
    end
  end

  defp tie_breaker_cell(_week, entry), do: entry.tie_breaker || ""

  defp coins_cell(_week, entry), do: format_coins(entry.coins_won)

  defp format_coins(nil), do: ""
  defp format_coins(n) when is_integer(n), do: n

  defp format_coins(n) when is_float(n) do
    rounded = Float.round(n, 1)

    if rounded == Float.round(rounded, 0) do
      trunc(rounded)
    else
      rounded
    end
  end

  defp format_coins(n), do: n
end
