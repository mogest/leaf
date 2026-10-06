defmodule Leaf.ReportsTest do
  use Leaf.DataCase, async: true

  alias Leaf.Audit.Entry
  alias Leaf.Fixtures
  alias Leaf.Leave
  alias Leaf.People
  alias Leaf.Policies
  alias Leaf.Reports

  @heading "Id,Name,Leave Type,First Day,Last Day,Hours,Days,Reason\r\n"

  setup do
    %{organisation: organisation, manager: manager, person: person, leave_type: leave_type} =
      Fixtures.workplace()

    {:ok, person} = People.update_person(person, nil, %{employee_number: "1001"})
    {:ok, leave_type} = Policies.update_leave_type(leave_type, nil, %{payroll_code: "AL"})

    %{organisation: organisation, manager: manager, person: person, leave_type: leave_type}
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

    {Reports.csv(table, People.time_zone(person)), table.notes}
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

  test "leave taken counts only its days in the period, narrowed by country and type", context do
    %{organisation: organisation, person: person, leave_type: leave_type} = context
    new_zealand = Fixtures.calendar(%{organisation_id: organisation.id})

    auckland =
      Fixtures.calendar(%{
        organisation_id: organisation.id,
        parent_id: new_zealand.id,
        name: "Auckland"
      })

    australia =
      Fixtures.calendar(%{
        organisation_id: organisation.id,
        name: "Australia",
        country_code: "AU",
        time_zone: "Australia/Sydney"
      })

    sick =
      Fixtures.leave_type(%{
        organisation_id: organisation.id,
        name: "Sick leave",
        unit: :days,
        position: 2
      })

    other = Fixtures.person(%{organisation_id: organisation.id, name: "Wren Okafor"})
    Fixtures.work_pattern(%{person_id: other.id})
    Fixtures.calendar_assignment(%{person_id: person.id, calendar_id: auckland.id})
    Fixtures.calendar_assignment(%{person_id: other.id, calendar_id: australia.id})

    take(person, leave_type, [
      {~D[2026-09-30], "8", :hours},
      {~D[2026-10-01], "8", :hours},
      {~D[2026-10-02], "4", :hours}
    ])

    take(person, sick, [{~D[2026-10-05], "1", :days}])
    take(other, leave_type, [{~D[2026-10-06], "8", :hours}])
    unpatterned = Fixtures.person(%{organisation_id: organisation.id, name: "Tui Hemara"})
    take(unpatterned, leave_type, [{~D[2026-10-09], "8", :hours}])
    take(person, leave_type, [{~D[2026-10-07], "8", :hours}], %{status: :cancelled})

    october = %{"report" => "taken", "from" => "2026-10-01", "to" => "2026-10-31"}

    assert csv(person, october) ==
             {"Person,Country,Leave type,Hours,Days\r\n" <>
                "Rae Halloran,New Zealand,Annual leave,12.00,1.50\r\n" <>
                "Rae Halloran,New Zealand,Sick leave,8.00,1.00\r\n" <>
                "Wren Okafor,Australia,Annual leave,8.00,1.00\r\n",
              ["Tui Hemara's work pattern does not cover their leave, so it is left out."]}

    narrowed =
      Map.merge(october, %{"country_id" => new_zealand.id, "leave_type_id" => leave_type.id})

    assert csv(person, narrowed) ==
             {"Person,Country,Leave type,Hours,Days\r\n" <>
                "Rae Halloran,New Zealand,Annual leave,12.00,1.50\r\n", []}
  end

  test "reconciliation lists what changed after the reader's cut-off to leave in the period",
       context do
    %{organisation: organisation, person: person, manager: manager, leave_type: leave_type} =
      context

    calendar = Fixtures.calendar(%{organisation_id: organisation.id})
    Fixtures.calendar_assignment(%{person_id: person.id, calendar_id: calendar.id})
    filed = &Fixtures.pending_request(person, %{leave_type_id: leave_type.id, dates: [&1]})

    at =
      &Repo.update_all(from(entry in Entry, where: entry.entity_id == ^&1.id),
        set: [inserted_at: &2]
      )

    moved = filed.(~D[2026-10-07])
    cancelled = filed.(~D[2026-10-08])
    declined = filed.(~D[2026-10-09])
    {:ok, _approved} = Leave.approve(moved, manager)
    {:ok, _approved} = Leave.approve(cancelled, manager)

    # Midnight in Auckland, where the reader is, is 11:00 the day before in UTC.
    Repo.update_all(Entry, set: [inserted_at: ~U[2026-09-30 10:59:00.000000Z]])
    at.(filed.(~D[2026-10-13]), ~U[2026-09-30 11:01:00.000000Z])

    {:ok, _amended} =
      Leave.amend(moved, manager, %{
        days: [%{leave_type_id: leave_type.id, date: ~D[2026-11-02], amount: "8", unit: :hours}]
      })

    {:ok, _cancelled} = Leave.cancel(cancelled, manager)
    {:ok, _declined} = Leave.decline(declined, manager)
    filed.(~D[2026-10-12])
    filed.(~D[2026-11-03])

    {:ok, table} =
      Reports.run(person, %{
        "report" => "reconciliation",
        "from" => "2026-10-01",
        "to" => "2026-10-31",
        "cut_off" => "2026-09-30"
      })

    zone = People.time_zone(person)
    [_heading, first | _rest] = String.split(Reports.csv(table, zone), "\r\n")

    assert first ==
             "01/10/2026 00:01,Filed,Rae Halloran,Annual leave,13/10/2026,13/10/2026,8.00,1.00,pending"

    assert Reports.csv(
             %{table | columns: tl(table.columns), rows: Enum.map(table.rows, &tl/1)},
             zone
           ) ==
             "Change,Person,Leave type,First day,Last day,Hours,Days,Status now\r\n" <>
               "Filed,Rae Halloran,Annual leave,13/10/2026,13/10/2026,8.00,1.00,pending\r\n" <>
               "Amended,Rae Halloran,Annual leave,02/11/2026,02/11/2026,8.00,1.00,approved\r\n" <>
               "Cancelled,Rae Halloran,Annual leave,08/10/2026,08/10/2026,8.00,1.00,cancelled\r\n" <>
               "Filed,Rae Halloran,Annual leave,12/10/2026,12/10/2026,8.00,1.00,pending\r\n"
  end

  test "balances and what lapses soon are read off each person's ledger as at a date", context do
    %{organisation: organisation, person: person} = context

    sick =
      Fixtures.leave_type(%{
        organisation_id: organisation.id,
        name: "Sick leave",
        unit: :days,
        position: 2
      })

    [assignment] = People.policy_assignments(person)

    Fixtures.policy_entitlement(%{
      leave_policy_id: assignment.leave_policy_id,
      leave_type_id: sick.id,
      grant_amount: "10",
      grant_timing: :period_start,
      pro_rated_by_fte: false,
      expiry_rule: :grant_period_end
    })

    take(person, sick, [{~D[2026-01-05], "1", :days}])
    as_at = %{"as_at" => "2026-02-01"}
    # Their manager has no work pattern, so nothing of theirs can be worked out.
    unready = ["Ines Vasquez's work pattern does not cover their leave, so it is left out."]

    assert csv(person, Map.put(as_at, "report", "balances")) ==
             {"Person,Sick leave (days)\r\nRae Halloran,9.00\r\n", unready}

    expiring = Map.put(as_at, "report", "expiring")

    # 3 March is 30 days on.
    assert csv(person, Map.put(expiring, "within", "29")) ==
             {"Person,Leave type,Amount,Unit,Lapses on\r\n", unready}

    assert csv(person, Map.put(expiring, "within", "30")) ==
             {"Person,Leave type,Amount,Unit,Lapses on\r\n" <>
                "Rae Halloran,Sick leave,9.00,days,03/03/2026\r\n", unready}
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
