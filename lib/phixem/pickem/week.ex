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
    field :starts_on, :date

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
      :tie_breaker_value,
      :starts_on
    ])
    |> validate_required([:number, :tab, :title, :matchups, :starts_on])
    |> validate_inclusion(:tab, ["last_week", "upcoming", "stored"])
    |> validate_sunday_start()
    |> unique_constraint(:number)
  end

  def matchup_list(%__MODULE__{matchups: matchups}) when is_binary(matchups) do
    matchups |> String.split(",", trim: true)
  end

  def matchup_teams(matchup) when is_binary(matchup) do
    case String.split(matchup, "@", parts: 2) do
      [away, home] -> {away, home}
      _ -> nil
    end
  end

  defp validate_sunday_start(changeset) do
    validate_change(changeset, :starts_on, fn :starts_on, date ->
      if Date.day_of_week(date) == 7 do
        []
      else
        [starts_on: "must be a Sunday"]
      end
    end)
  end
end
