defmodule Leaf.DatesTest do
  use ExUnit.Case, async: true

  alias Leaf.Dates

  test "midnight is when the day begins, even where the clocks change at midnight" do
    assert Dates.midnight(~D[2026-10-01], "Pacific/Auckland") ==
             DateTime.new!(~D[2026-10-01], ~T[00:00:00], "Pacific/Auckland")

    # Havana skips from midnight to one in March, and goes back from one to midnight in November.
    assert Dates.midnight(~D[2026-03-08], "America/Havana") ==
             DateTime.new!(~D[2026-03-08], ~T[01:00:00], "America/Havana")

    assert DateTime.shift_zone!(Dates.midnight(~D[2026-11-01], "America/Havana"), "Etc/UTC") ==
             ~U[2026-11-01 04:00:00Z]
  end
end
