defmodule Phixem.Eastern do
  @moduledoc false

  def from_utc(%DateTime{} = utc) do
    utc = DateTime.shift_zone!(utc, "Etc/UTC")
    offset_hours = if dst?(utc), do: -4, else: -5
    DateTime.add(utc, offset_hours * 3600, :second)
  end

  def pickem_sunday(%DateTime{} = utc) do
    eastern = from_utc(utc)
    date = DateTime.to_date(eastern)
    weekday = Date.day_of_week(date)

    cond do
      weekday == 7 -> date
      weekday == 1 -> Date.add(date, -1)
      weekday == 2 and eastern.hour < 12 -> Date.add(date, -2)
      weekday == 2 -> Date.add(date, 5)
      true -> Date.add(date, 7 - weekday)
    end
  end

  # Thursday 10pm inclusive through Friday 3am exclusive;
  # Sunday noon inclusive through Tuesday 3am exclusive.
  def score_fetch_window?(%DateTime{} = utc) do
    eastern = from_utc(utc)
    weekday = Date.day_of_week(DateTime.to_date(eastern))
    minutes = eastern.hour * 60 + eastern.minute

    cond do
      weekday == 4 and minutes >= 22 * 60 -> true
      weekday == 5 and minutes < 3 * 60 -> true
      weekday == 7 and minutes >= 12 * 60 -> true
      weekday == 1 -> true
      weekday == 2 and minutes < 3 * 60 -> true
      true -> false
    end
  end

  defp dst?(%DateTime{} = utc) do
    year = utc.year
    dst_start = utc_at(nth_sunday(year, 3, 2), ~T[07:00:00])
    dst_end = utc_at(nth_sunday(year, 11, 1), ~T[06:00:00])

    DateTime.compare(utc, dst_start) != :lt and DateTime.compare(utc, dst_end) == :lt
  end

  defp nth_sunday(year, month, n) do
    first = Date.new!(year, month, 1)
    Date.add(first, rem(7 - Date.day_of_week(first), 7) + 7 * (n - 1))
  end

  defp utc_at(%Date{} = date, %Time{} = time) do
    DateTime.from_naive!(NaiveDateTime.new!(date, time), "Etc/UTC")
  end
end
