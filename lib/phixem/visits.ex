defmodule Phixem.Visits do
  @moduledoc """
  Records page loads so persistence and live updates can be verified.
  """

  import Ecto.Query

  alias Phixem.Repo
  alias Phixem.Visits.PageLoad

  @topic "page_loads"

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Phixem.PubSub, @topic)
  end

  @spec list() :: [PageLoad.t()]
  def list do
    Repo.all(from p in PageLoad, order_by: [asc: p.id])
  end

  @spec record() :: PageLoad.t()
  def record do
    load =
      %PageLoad{}
      |> Ecto.Changeset.change()
      |> Repo.insert!()

    Phoenix.PubSub.broadcast(Phixem.PubSub, @topic, {:page_load, load})
    load
  end
end
