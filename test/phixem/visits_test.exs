defmodule Phixem.VisitsTest do
  use Phixem.DataCase

  alias Phixem.Visits

  test "record appends a row and list returns chronological loads" do
    first = Visits.record()
    assert Visits.list() == [first]

    second = Visits.record()
    assert Visits.list() == [first, second]
  end
end
