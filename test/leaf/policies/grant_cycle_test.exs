defmodule Leaf.Policies.GrantCycleTest do
  use ExUnit.Case, async: true

  alias Leaf.Policies.GrantCycle

  @anchors %{employment_start_date: ~D[2024-03-04], birth_date: nil, year_start_month: 1}

  defp cycle(basis, period, anchors \\ %{}) do
    {:ok, cycle} = GrantCycle.new(basis, period, Map.merge(@anchors, anchors))
    cycle
  end

  test "an anniversary year runs from the employment date" do
    cycle = cycle(:employment_date, :year)

    assert GrantCycle.period_containing(cycle, ~D[2026-08-22]) ==
             Date.range(~D[2026-03-04], ~D[2027-03-03])

    assert GrantCycle.period_containing(cycle, ~D[2026-01-15]) ==
             Date.range(~D[2025-03-04], ~D[2026-03-03])
  end

  test "quarters and months run from the employment date too" do
    assert GrantCycle.period_containing(cycle(:employment_date, :quarter), ~D[2026-08-22]) ==
             Date.range(~D[2026-06-04], ~D[2026-09-03])

    assert GrantCycle.period_containing(cycle(:employment_date, :month), ~D[2026-08-22]) ==
             Date.range(~D[2026-08-04], ~D[2026-09-03])
  end

  test "a cycle pinned past the end of a month clamps without drifting" do
    cycle = cycle(:employment_date, :month, %{employment_start_date: ~D[2024-01-31]})

    assert GrantCycle.period_containing(cycle, ~D[2024-02-15]) ==
             Date.range(~D[2024-01-31], ~D[2024-02-28])

    assert GrantCycle.period_containing(cycle, ~D[2024-03-01]) ==
             Date.range(~D[2024-02-29], ~D[2024-03-30])

    assert GrantCycle.period_containing(cycle, ~D[2024-03-31]) ==
             Date.range(~D[2024-03-31], ~D[2024-04-29])
  end

  test "a birthday cycle keeps a 29 February birthday" do
    cycle = cycle(:birthday, :year, %{birth_date: ~D[1992-02-29]})

    assert GrantCycle.period_containing(cycle, ~D[2024-06-01]) ==
             Date.range(~D[2024-02-29], ~D[2025-02-27])

    assert GrantCycle.period_containing(cycle, ~D[2025-06-01]) ==
             Date.range(~D[2025-02-28], ~D[2026-02-27])
  end

  test "a birthday cycle needs a birth date" do
    assert GrantCycle.new(:birthday, :year, @anchors) == :error
  end

  test "a calendar year is the calendar year, whenever the organisation's year starts" do
    cycle = cycle(:calendar_year, :year, %{year_start_month: 4})

    assert GrantCycle.period_containing(cycle, ~D[2026-08-22]) ==
             Date.range(~D[2026-01-01], ~D[2026-12-31])
  end

  test "an organisation year runs from the month the organisation's year starts" do
    cycle = cycle(:organisation_year, :year, %{year_start_month: 4})

    assert GrantCycle.period_containing(cycle, ~D[2026-08-22]) ==
             Date.range(~D[2026-04-01], ~D[2027-03-31])

    assert GrantCycle.period_containing(cycle, ~D[2026-02-10]) ==
             Date.range(~D[2025-04-01], ~D[2026-03-31])
  end

  test "organisation quarters take their phase from that month" do
    cycle = cycle(:organisation_year, :quarter, %{year_start_month: 4})

    assert GrantCycle.period_containing(cycle, ~D[2026-08-22]) ==
             Date.range(~D[2026-07-01], ~D[2026-09-30])
  end

  test "every period a range touches comes back in order" do
    cycle = cycle(:employment_date, :year)

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
    cycle = cycle(:employment_date, :year)

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
