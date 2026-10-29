defmodule Phixem.VisitsTest do
  use Phixem.DataCase

  alias Phixem.Visits

  test "record_and_list appends a row and returns chronological loads" do
    first = Visits.record_and_list()
    assert length(first) == 1

    second = Visits.record_and_list()
    assert length(second) == 2
    assert hd(second).id == hd(first).id
  end
end
