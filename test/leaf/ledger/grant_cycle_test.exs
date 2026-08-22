defmodule Leaf.Ledger.GrantCycleTest do
  use ExUnit.Case, async: true

  alias Leaf.Ledger.GrantCycle

  test "a yearly cycle runs from the day it is pinned to" do
    cycle = GrantCycle.new(3, 4, :year)

    assert GrantCycle.period_containing(cycle, ~D[2026-08-22]) ==
             Date.range(~D[2026-03-04], ~D[2027-03-03])

    assert GrantCycle.period_containing(cycle, ~D[2026-01-15]) ==
             Date.range(~D[2025-03-04], ~D[2026-03-03])
  end

  test "quarters and months run from that day too" do
    assert GrantCycle.period_containing(GrantCycle.new(3, 4, :quarter), ~D[2026-08-22]) ==
             Date.range(~D[2026-06-04], ~D[2026-09-03])

    assert GrantCycle.period_containing(GrantCycle.new(3, 4, :month), ~D[2026-08-22]) ==
             Date.range(~D[2026-08-04], ~D[2026-09-03])
  end

  test "a cycle pinned past the end of a month clamps without drifting" do
    cycle = GrantCycle.new(1, 31, :month)

    assert GrantCycle.period_containing(cycle, ~D[2024-02-15]) ==
             Date.range(~D[2024-01-31], ~D[2024-02-28])

    assert GrantCycle.period_containing(cycle, ~D[2024-03-01]) ==
             Date.range(~D[2024-02-29], ~D[2024-03-30])

    assert GrantCycle.period_containing(cycle, ~D[2024-03-31]) ==
             Date.range(~D[2024-03-31], ~D[2024-04-29])
  end

  test "a cycle pinned to 29 February keeps it" do
    cycle = GrantCycle.new(2, 29, :year)

    assert GrantCycle.period_containing(cycle, ~D[2024-06-01]) ==
             Date.range(~D[2024-02-29], ~D[2025-02-27])

    assert GrantCycle.period_containing(cycle, ~D[2025-06-01]) ==
             Date.range(~D[2025-02-28], ~D[2026-02-27])
  end

  test "a cycle pinned to the first of a month runs the year from there" do
    assert GrantCycle.period_containing(GrantCycle.new(1, 1, :year), ~D[2026-08-22]) ==
             Date.range(~D[2026-01-01], ~D[2026-12-31])

    assert GrantCycle.period_containing(GrantCycle.new(4, 1, :year), ~D[2026-08-22]) ==
             Date.range(~D[2026-04-01], ~D[2027-03-31])

    assert GrantCycle.period_containing(GrantCycle.new(4, 1, :year), ~D[2026-02-10]) ==
             Date.range(~D[2025-04-01], ~D[2026-03-31])
  end

  test "quarters take their phase from the month they are pinned to" do
    assert GrantCycle.period_containing(GrantCycle.new(4, 1, :quarter), ~D[2026-08-22]) ==
             Date.range(~D[2026-07-01], ~D[2026-09-30])
  end

  test "every period a range touches comes back in order" do
    cycle = GrantCycle.new(3, 4, :year)

    assert GrantCycle.periods_overlapping(cycle, Date.range(~D[2025-01-01], ~D[2026-05-01])) == [
             Date.range(~D[2024-03-04], ~D[2025-03-03]),
             Date.range(~D[2025-03-04], ~D[2026-03-03]),
             Date.range(~D[2026-03-04], ~D[2027-03-03])
           ]

    assert GrantCycle.periods_overlapping(cycle, Date.range(~D[2025-04-01], ~D[2025-04-30])) == [
             Date.range(~D[2025-03-04], ~D[2026-03-03])
           ]
  end

  test "a range ending on a period's last day stops there" do
    cycle = GrantCycle.new(3, 4, :year)

    assert GrantCycle.periods_overlapping(cycle, Date.range(~D[2025-03-04], ~D[2026-03-03])) == [
             Date.range(~D[2025-03-04], ~D[2026-03-03])
           ]

    assert GrantCycle.periods_overlapping(cycle, Date.range(~D[2026-03-03], ~D[2026-03-03])) == [
             Date.range(~D[2025-03-04], ~D[2026-03-03])
           ]

    assert GrantCycle.periods_overlapping(cycle, Date.range(~D[2026-03-03], ~D[2026-03-04])) == [
             Date.range(~D[2025-03-04], ~D[2026-03-03]),
             Date.range(~D[2026-03-04], ~D[2027-03-03])
           ]
  end
end
