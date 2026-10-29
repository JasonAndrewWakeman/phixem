defmodule Phixem.Visits do
  @moduledoc """
  Records HTTP page loads so persistence across scale-to-zero can be verified.
  """

  import Ecto.Query

  alias Phixem.Repo
  alias Phixem.Visits.PageLoad

  @spec record_and_list() :: [PageLoad.t()]
  def record_and_list do
    %PageLoad{}
    |> Ecto.Changeset.change()
    |> Repo.insert!()

    Repo.all(from p in PageLoad, order_by: [asc: p.id])
  end
end
