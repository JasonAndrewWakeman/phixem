defmodule PhixemWeb.PageLive do
  use PhixemWeb, :live_view

  alias Phixem.Pickem
  alias Phixem.Pickem.{Entry, Week}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Phixem.PubSub, "pickem")
    end

    {:ok, assign(socket, :weeks, Pickem.list_weeks())}
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
  end

  defp assign_week(socket, week) do
    socket
    |> assign(:week_number, week.number)
    |> assign(:week, week)
    |> assign(:matchups, Week.matchup_list(week))
    |> assign(:entries, week.entries)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>
      Phixem
      <span class="header-stats">
        TOTAL ENTRIES {player_count(@entries)}
        TOTAL POT: {pot(@entries)}
      </span>
    </h1>
    <p class="muted">
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
          <tr :for={entry <- @entries} class={if entry.winners_row, do: "winners"}>
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

  defp player_count(entries) do
    Enum.count(entries, &(&1.winners_row == false))
  end

  defp pot(entries) do
    case Enum.find(entries, & &1.winners_row) do
      %{coins_won: coins} when is_integer(coins) -> coins
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

  defp coins_cell(_week, entry), do: blank(entry.coins_won)
end
