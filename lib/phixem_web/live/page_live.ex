defmodule PhixemWeb.PageLive do
  use PhixemWeb, :live_view

  alias Phixem.Visits

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :ok = Visits.subscribe()
      Visits.record()
    end

    {:ok, assign(socket, page_loads: Visits.list())}
  end

  @impl true
  def handle_info({:page_load, load}, socket) do
    {:noreply, update(socket, :page_loads, &append_load(&1, load))}
  end

  defp append_load(loads, load) do
    if Enum.any?(loads, &(&1.id == load.id)), do: loads, else: loads ++ [load]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Phixem</h1>
    <p>
      Each connected browser records a UTC load time in SQLite. Open this page in
      another tab: the list updates here without a refresh.
    </p>
    <p class="muted">{length(@page_loads)} load(s) recorded.</p>
    <ol>
      <li
        :for={{load, index} <- Enum.with_index(@page_loads, 1)}
        class={if index == length(@page_loads), do: "this"}
      >
        {Calendar.strftime(load.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
        <span :if={index == length(@page_loads)} class="this"> — latest</span>
      </li>
    </ol>
    """
  end
end
