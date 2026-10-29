defmodule Phixem.Pickem.Week do
  use Ecto.Schema
  import Ecto.Changeset

  schema "nfl_weeks" do
    field :number, :integer
    field :tab, :string
    field :title, :string
    field :matchups, :string
    field :complete, :boolean, default: false
    field :mnf_score, :string
    field :tie_breaker_value, :integer

    has_many :entries, Phixem.Pickem.Entry

    timestamps(type: :utc_datetime)
  end

  def changeset(week, attrs) do
    week
    |> cast(attrs, [
      :number,
      :tab,
      :title,
      :matchups,
      :complete,
      :mnf_score,
      :tie_breaker_value
    ])
    |> validate_required([:number, :tab, :title, :matchups])
    |> unique_constraint(:number)
    |> unique_constraint(:tab)
  end

  def matchup_list(%__MODULE__{matchups: matchups}) when is_binary(matchups) do
    matchups |> String.split(",", trim: true)
  end
end
