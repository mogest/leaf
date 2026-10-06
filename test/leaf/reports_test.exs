defmodule Leaf.ReportsTest do
  use Leaf.DataCase, async: true

  alias Leaf.Fixtures
  alias Leaf.People
  alias Leaf.Policies
  alias Leaf.Reports

  @heading "Id,Name,Leave Type,First Day,Last Day,Hours,Days,Reason\r\n"

  setup do
    %{organisation: organisation, person: person, leave_type: leave_type} = Fixtures.workplace()
    {:ok, person} = People.update_person(person, nil, %{employee_number: "1001"})
    {:ok, leave_type} = Policies.update_leave_type(leave_type, nil, %{payroll_code: "AL"})

    %{organisation: organisation, person: person, leave_type: leave_type}
  end

  defp take(person, leave_type, days, attrs \\ %{}) do
    days =
      Enum.map(days, fn {date, amount, unit} ->
        %{leave_type_id: leave_type.id, date: date, amount: amount, unit: unit}
      end)

    Fixtures.leave_request(Map.merge(%{person_id: person.id, days: days}, attrs))
  end

  defp csv(person, params) do
    {:ok, table} = Reports.run(person, params)

    {Reports.csv(table), table.notes}
  end

  defp ipayroll(person, from, to) do
    csv(person, %{"report" => "ipayroll", "from" => from, "to" => to})
  end

  describe "the iPayroll export" do
    test "takes each approved request whole into the period its first day falls in", context do
      %{organisation: organisation, person: person, leave_type: leave_type} = context

      sick =
        Fixtures.leave_type(%{
          organisation_id: organisation.id,
          name: "Sick leave",
          position: 2,
          payroll_code: "SICK"
        })

      take(
        person,
        leave_type,
        [
          {~D[2026-09-30], "8", :hours},
          {~D[2026-10-01], "1", :days},
          {~D[2026-10-02], "4", :hours}
        ],
        %{note: ~s(The "big" wedding, out of town)}
      )

      Fixtures.leave_request(%{
        person_id: person.id,
        days: [
          %{leave_type_id: sick.id, date: ~D[2026-10-06], amount: "1", unit: :days},
          %{leave_type_id: leave_type.id, date: ~D[2026-10-05], amount: "1", unit: :days}
        ]
      })

      take(person, leave_type, [{~D[2026-10-07], "1", :days}], %{status: :pending})
      take(person, leave_type, [{~D[2026-10-08], "1", :days}], %{status: :declined})
      take(person, leave_type, [{~D[2026-10-09], "1", :days}], %{status: :cancelled})

      assert ipayroll(person, "2026-09-01", "2026-09-30") ==
               {@heading <>
                  "1001,Rae Halloran,AL,30/09/2026,02/10/2026,20.00,2.50," <>
                  ~s("The ""big"" wedding, out of town"\r\n), []}

      assert ipayroll(person, "2026-10-01", "2026-10-31") ==
               {@heading <>
                  "1001,Rae Halloran,AL,05/10/2026,05/10/2026,8.00,1.00,\r\n" <>
                  "1001,Rae Halloran,SICK,06/10/2026,06/10/2026,8.00,1.00,\r\n", []}
    end

    test "leaves out an uncoded type and unmeasurable leave, and blanks a missing id, saying so",
         context do
      %{organisation: organisation, person: person, leave_type: leave_type} = context
      uncoded = Fixtures.leave_type(%{organisation_id: organisation.id, name: "Quarterly leave"})
      other = Fixtures.person(%{organisation_id: organisation.id, name: "Ines Vasquez"})
      Fixtures.work_pattern(%{person_id: other.id})
      unpatterned = Fixtures.person(%{organisation_id: organisation.id, name: "Tui Hemara"})

      take(person, uncoded, [{~D[2026-10-05], "8", :hours}, {~D[2026-10-06], "8", :hours}])
      take(person, uncoded, [{~D[2026-10-08], "8", :hours}])
      take(other, leave_type, [{~D[2026-10-07], "8", :hours}])
      take(unpatterned, leave_type, [{~D[2026-10-09], "8", :hours}])

      assert ipayroll(person, "2026-10-01", "2026-10-31") ==
               {@heading <> ",Ines Vasquez,AL,07/10/2026,07/10/2026,8.00,1.00,\r\n",
                [
                  "Quarterly leave has no payroll code, so it is left out of 2 requests.",
                  "Ines Vasquez has no employee number, so the Id on their rows is blank.",
                  "Tui Hemara's work pattern does not cover their leave, so it is left out."
                ]}
    end
  end

  test "a period that ends before it starts is refused", %{person: person} do
    assert {:error, changeset} =
             Reports.run(person, %{
               "report" => "ipayroll",
               "from" => "2026-10-31",
               "to" => "2026-10-01"
             })

    assert "must not be before from" in errors_on(changeset).to
  end
end
