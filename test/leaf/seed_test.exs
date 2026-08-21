defmodule Leaf.SeedTest do
  use Leaf.DataCase, async: true

  alias Leaf.Org
  alias Leaf.People
  alias Leaf.Policies
  alias Leaf.Seed

  test "the example organisation is configured as SCOPE.md describes it" do
    %{organisation: organisation, policy: policy, person: person} = Seed.run()

    entitlements = Policies.entitlements(policy.id, Date.range(~D[2026-01-01], ~D[2026-12-31]))

    assert Enum.map(entitlements, & &1.leave_type.name) == [
             "Annual leave",
             "Sick leave",
             "Quarterly leave",
             "Birthday leave",
             "Longevity leave",
             "Bereavement leave"
           ]

    assert {:ok, pattern} = People.fetch_work_pattern(person, person.employment_start_date)
    assert Decimal.equal?(People.fte(pattern, organisation.full_time_week_hours), "0.9")

    assert [{_span, calendar_id}] =
             People.holiday_calendar_segments(person, Date.range(~D[2026-01-01], ~D[2026-12-31]))

    assert length(Org.public_holidays(calendar_id, Date.range(~D[2026-01-01], ~D[2026-12-31]))) ==
             11
  end

  test "quarterly leave pro-rates to the person's hours" do
    %{organisation: organisation, policy: policy, person: person} = Seed.run()

    entitlements = Policies.entitlements(policy.id, Date.range(~D[2026-01-01], ~D[2026-03-31]))
    quarterly = Enum.find(entitlements, &(&1.leave_type.name == "Quarterly leave"))

    {:ok, pattern} = People.fetch_work_pattern(person, ~D[2026-01-01])
    fte = People.fte(pattern, organisation.full_time_week_hours)

    assert Decimal.equal?(Decimal.mult(quarterly.grant_amount, fte), "7.2")
  end
end
