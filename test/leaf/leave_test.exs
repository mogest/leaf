defmodule Leaf.LeaveTest do
  use Leaf.DataCase, async: true

  alias Leaf.Fixtures
  alias Leaf.Leave

  setup do
    organisation = Fixtures.organisation()
    person = Fixtures.person(%{organisation_id: organisation.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})

    %{organisation: organisation, person: person, leave_type: leave_type}
  end

  defp request(person, leave_type, status, dates) do
    Fixtures.leave_request(%{
      person_id: person.id,
      submitted_by_id: person.id,
      status: status,
      days: Enum.map(dates, &%{leave_type_id: leave_type.id, date: &1, hours: "8", days: "1"})
    })
  end

  test "only approved leave up to the date asked about counts as taken", context do
    %{person: person, leave_type: leave_type} = context
    request(person, leave_type, :approved, [~D[2023-11-02], ~D[2024-03-05]])
    request(person, leave_type, :pending, [~D[2024-03-06]])
    request(person, leave_type, :cancelled, [~D[2024-03-07]])
    request(person, leave_type, :approved, [~D[2024-06-01]])

    taken = Leave.days_taken(person, ~D[2024-03-31])

    assert Enum.map(taken, & &1.date) == [~D[2023-11-02], ~D[2024-03-05]]
  end

  test "balance entries come back oldest first, up to the date asked about", context do
    %{person: person, leave_type: leave_type} = context
    base = %{person_id: person.id, leave_type_id: leave_type.id}

    {:ok, _opening} =
      Leave.create_balance_entry(
        Map.merge(base, %{date: ~D[2024-01-01], kind: :opening_balance, amount: "40"})
      )

    {:ok, _adjustment} =
      Leave.create_balance_entry(
        Map.merge(base, %{
          date: ~D[2024-06-01],
          kind: :adjustment,
          amount: "-4",
          reason: "Duplicated on import"
        })
      )

    {:ok, _later} =
      Leave.create_balance_entry(
        Map.merge(base, %{date: ~D[2025-01-01], kind: :opening_balance, amount: "8"})
      )

    entries = Leave.balance_entries(person, ~D[2024-12-31])

    assert Enum.map(entries, & &1.kind) == [:opening_balance, :adjustment]
  end
end
