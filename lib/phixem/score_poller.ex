defmodule Phixem.ScorePoller do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms) || config(:interval_ms, :timer.minutes(15))
    send(self(), :tick)
    {:ok, %{interval: interval, task: nil}}
  end

  @impl true
  def handle_info(:tick, state) do
    state =
      if Phixem.Eastern.score_fetch_window?(DateTime.utc_now()) do
        ensure_task(state)
      else
        state
      end

    {:noreply, schedule(state)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{task: pid} = state) do
    {:noreply, %{state | task: nil}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  defp ensure_task(%{task: pid} = state) when is_pid(pid) do
    if Process.alive?(pid), do: state, else: spawn_sync(state)
  end

  defp ensure_task(state), do: spawn_sync(state)

  defp spawn_sync(state) do
    {:ok, pid} =
      Task.Supervisor.start_child(Phixem.TaskSupervisor, fn ->
        Phixem.ScoreSync.sync_current_week()
      end)

    Process.monitor(pid)
    %{state | task: pid}
  end

  defp schedule(state) do
    Process.send_after(self(), :tick, state.interval)
    state
  end

  defp config(key, default) do
    :phixem
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end
end
