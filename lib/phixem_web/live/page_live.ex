defmodule PhixemWeb.PageLive do
  use PhixemWeb, :live_view

  alias Phixem.Pickem
  alias Phixem.Pickem.{Entry, Week}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_tab(socket, "upcoming")}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign_tab(socket, tab)}
  end

  defp assign_tab(socket, tab) do
    week = Pickem.get_week_by_tab(tab)

    socket
    |> assign(:tab, tab)
    |> assign(:week, week)
    |> assign(:matchups, if(week, do: Week.matchup_list(week), else: []))
    |> assign(:entries, if(week, do: week.entries, else: []))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Phixem</h1>
    <p class="muted">NFL pick board. Headers stay fixed. PERFECT is the winners row.</p>

    <div class="tabs" role="tablist">
      <button
        type="button"
        role="tab"
        class={if @tab == "last_week", do: "tab on", else: "tab"}
        phx-click="select_tab"
        phx-value-tab="last_week"
      >
        Last week
      </button>
      <button
        type="button"
        role="tab"
        class={if @tab == "upcoming", do: "tab on", else: "tab"}
        phx-click="select_tab"
        phx-value-tab="upcoming"
      >
        Upcoming week
      </button>
    </div>

    <p :if={is_nil(@week)} class="muted">No week seeded yet. Run mix run priv/repo/seeds.exs</p>

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
            <td>{blank(entry.correct_choices)}</td>
            <td>{coins_cell(@week, entry)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp pick(entry, matchup) do
    entry |> Entry.pick_map() |> Map.get(matchup, "")
  end

  defp blank(nil), do: ""
  defp blank(value), do: value

  defp tie_breaker_cell(week, %{winners_row: true} = entry) do
    cond do
      is_binary(week.mnf_score) and week.mnf_score != "" -> week.mnf_score
      is_binary(entry.tie_breaker) -> entry.tie_breaker
      true -> ""
    end
  end

  defp tie_breaker_cell(_week, entry), do: entry.tie_breaker || ""

  defp coins_cell(%{complete: true}, entry), do: blank(entry.coins_won)
  defp coins_cell(_week, %{winners_row: true}), do: ""
  defp coins_cell(_week, _entry), do: ""
end
