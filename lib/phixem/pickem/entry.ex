defmodule Phixem.Pickem.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "nfl_entries" do
    field :username, :string
    field :winners_row, :boolean, default: false
    field :picks, :string, default: "{}"
    field :tie_breaker, :string
    field :correct_choices, :integer
    field :coins_won, :integer
    field :total_coins_won, :integer

    belongs_to :week, Phixem.Pickem.Week

    timestamps(type: :utc_datetime)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :week_id,
      :username,
      :winners_row,
      :picks,
      :tie_breaker,
      :correct_choices,
      :coins_won,
      :total_coins_won
    ])
    |> validate_required([:week_id, :username, :picks])
  end

  def pick_map(%__MODULE__{picks: picks}) when is_binary(picks) do
    case Jason.decode(picks) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end
end
