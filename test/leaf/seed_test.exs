defmodule Leaf.SeedTest do
  use Leaf.DataCase, async: true

  alias Leaf.Ledger
  alias Leaf.Org
  alias Leaf.People
  alias Leaf.Policies
  alias Leaf.Seed

  defp names(policy, range) do
    Enum.map(Policies.entitlements(policy.id, range), & &1.leave_type.name)
  end

  defp balance(person, leave_type_name, as_at) do
    statement =
      Enum.find(Ledger.statements(person, as_at), &(&1.leave_type.name == leave_type_name))

    statement.balance
  end

  test "the example organisation is configured as SCOPE.md describes it" do
    %{organisation: organisation, policies: policies, people: people} = Seed.run()
    year = Date.range(~D[2026-01-01], ~D[2026-12-31])

    assert names(policies["New Zealand employee"], year) == [
             "Annual leave",
             "Sick leave",
             "Quarterly leave",
             "Birthday leave",
             "Longevity leave",
             "Bereavement leave"
           ]

    assert names(policies["New Zealand contractor"], year) == [
             "Annual leave",
             "Public holiday allowance",
             "Bereavement leave"
           ]

    person = people["Mog"]

    assert {:ok, pattern} = People.fetch_work_pattern_on(person, person.employment_start_date)
    assert Decimal.equal?(People.fte(pattern, organisation.full_time_week_hours), "0.9")

    assert [{_span, calendar_id}] = People.holiday_calendar_segments(person, year)
    assert length(Org.public_holidays(calendar_id, year)) == 11
  end

  test "quarterly leave grants the person's share of it at the start of the quarter" do
    %{people: people} = Seed.run()

    assert Decimal.equal?(balance(people["Mog"], "Quarterly leave", ~D[2026-01-05]), "7.20")
  end

  test "the contractor is credited their share of the public holidays for their leave year" do
    %{people: people} = Seed.run()

    assert Decimal.equal?(
             balance(people["Ari Kelburn"], "Public holiday allowance", ~D[2025-01-01]),
             "44.00"
           )
  end
end
