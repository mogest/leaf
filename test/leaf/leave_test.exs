defmodule Leaf.LeaveTest do
  use Leaf.DataCase, async: true

  alias Leaf.Audit.Entry
  alias Leaf.Fixtures
  alias Leaf.Leave

  @thursday ~D[2026-08-20]
  @friday ~D[2026-08-21]
  @saturday ~D[2026-08-22]

  setup do
    organisation = Fixtures.organisation()
    manager = Fixtures.person(%{organisation_id: organisation.id, name: "Ines Vasquez"})

    admin =
      Fixtures.person(%{organisation_id: organisation.id, name: "Toma Ferrer", role: :admin})

    person =
      Fixtures.person(%{organisation_id: organisation.id, manager_id: manager.id})

    Fixtures.work_pattern(%{person_id: person.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})

    %{
      organisation: organisation,
      person: person,
      manager: manager,
      admin: admin,
      leave_type: leave_type
    }
  end

  defp entry(leave_type, date, attrs \\ %{}) do
    Map.merge(%{leave_type_id: leave_type.id, date: date, amount: "8", unit: :hours}, attrs)
  end

  defp file(context, dates, attrs \\ %{}) do
    days = Enum.map(dates, &entry(context.leave_type, &1, attrs))

    Leave.request(context.person, context.person, %{days: days, note: "Away"})
  end

  defp observes(context, holiday) do
    calendar = Fixtures.holiday_calendar(%{organisation_id: context.organisation.id})
    Fixtures.public_holiday(%{holiday_calendar_id: calendar.id, date: holiday})

    Fixtures.calendar_assignment(%{
      person_id: context.person.id,
      holiday_calendar_id: calendar.id
    })
  end

  defp on_policy(context, entitlement) do
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})

    Fixtures.policy_entitlement(
      Map.merge(entitlement, %{
        leave_policy_id: policy.id,
        leave_type_id: context.leave_type.id
      })
    )

    Fixtures.policy_assignment(%{person_id: context.person.id, leave_policy_id: policy.id})
  end

  defp taken(context) do
    Fixtures.leave_request(%{
      person_id: context.person.id,
      days: [entry(context.leave_type, @thursday)]
    })
  end

  test "a request is filed pending, in the unit it was asked for, and audited", context do
    assert {:ok, request} = file(context, [@thursday, @friday], %{amount: "1", unit: :days})

    assert request.status == :pending
    assert [%{amount: amount, unit: :days}, _friday] = Enum.sort_by(request.days, & &1.date)
    assert Decimal.equal?(amount, "1.00")

    assert [%{action: "leave_request.requested", subject_person_id: subject}] = Repo.all(Entry)
    assert subject == context.person.id
  end

  test "leave cannot be filed on a day the person does not work", context do
    assert {:error, changeset} = file(context, [@saturday])

    assert [%{date: ["is not a working day"]}] = errors_on(changeset).days
    assert Repo.all(Entry) == []
  end

  test "a public holiday the person is granted off is not a working day", context do
    observes(context, @friday)
    on_policy(context, %{})

    assert Leave.working_days(context.person, Date.range(@thursday, @saturday)) ==
             [{@thursday, Decimal.new("8.00")}]

    assert {:error, changeset} = file(context, [@friday])
    assert [%{date: ["is not a working day"]}] = errors_on(changeset).days
  end

  test "a public holiday is an ordinary day where the policy credits it instead", context do
    observes(context, @friday)
    on_policy(context, %{amount_source: :public_holidays, grant_amount: nil})

    assert Leave.working_days(context.person, Date.range(@thursday, @saturday)) ==
             [{@thursday, Decimal.new("8.00")}, {@friday, Decimal.new("8.00")}]

    assert {:ok, %{status: :pending}} = file(context, [@friday])
  end

  test "leave cannot be filed on a date with no work pattern on record", context do
    assert {:error, changeset} = file(context, [~D[2024-02-01]])
    assert [%{date: ["has no work pattern on record"]}] = errors_on(changeset).days
    assert Repo.all(Entry) == []
  end

  test "a colleague may not file leave for somebody else", context do
    days = [entry(context.leave_type, @thursday)]
    colleague = Fixtures.person(%{organisation_id: context.organisation.id})

    assert Leave.request(context.person, colleague, %{days: days}) == {:error, :forbidden}
  end

  test "the person may revise their own request only while it is pending", context do
    {:ok, pending} = file(context, [@thursday, @friday])
    {:ok, request} = Leave.fetch_request(pending.id)

    assert {:ok, shortened} =
             Leave.amend(request, context.person, %{
               days: [entry(context.leave_type, @thursday)]
             })

    assert length(shortened.days) == 1

    {:ok, request} = Leave.fetch_request(shortened.id)
    {:ok, approved} = Leave.approve(request, context.manager)
    {:ok, request} = Leave.fetch_request(approved.id)

    assert Leave.cancel(request, context.person) == {:error, :forbidden}
    assert {:ok, %{status: :cancelled}} = Leave.cancel(request, context.manager)
  end

  test "an approved request is amended by a manager, and no longer by the person", context do
    {:ok, pending} = file(context, [@thursday, @friday])
    {:ok, request} = Leave.fetch_request(pending.id)
    {:ok, approved} = Leave.approve(request, context.manager)
    {:ok, request} = Leave.fetch_request(approved.id)

    shortened = %{days: [entry(context.leave_type, @thursday)]}

    assert Leave.amend(request, context.person, shortened) == {:error, :forbidden}
    assert {:ok, amended} = Leave.amend(request, context.manager, shortened)

    assert amended.status == :approved
    assert [%{date: @thursday}] = amended.days
  end

  test "a decision records who made it, and only their manager or an admin may make it",
       context do
    {:ok, pending} = file(context, [@thursday])
    {:ok, request} = Leave.fetch_request(pending.id)

    assert Leave.approve(request, context.person) == {:error, :forbidden}
    assert {:ok, declined} = Leave.decline(request, context.admin, "Covering a release")

    assert declined.status == :declined
    assert declined.reviewed_by_id == context.admin.id
    assert declined.reviewed_at

    {:ok, request} = Leave.fetch_request(declined.id)

    assert Leave.approve(request, context.manager) == {:error, :forbidden}
  end

  test "only an administrator may enter a balance figure", context do
    attrs = %{leave_type_id: context.leave_type.id, date: @thursday, amount: "40"}

    assert Leave.create_balance_entry(context.person, context.manager, attrs) ==
             {:error, :forbidden}

    assert {:ok, opening} =
             Leave.create_balance_entry(
               context.person,
               context.admin,
               Map.put(attrs, :kind, :opening_balance)
             )

    assert opening.created_by_id == context.admin.id
    assert [%{action: "balance_entry.created"}] = Repo.all(Entry)
  end

  test "only approved leave up to the date asked about counts as taken", context do
    %{person: person, leave_type: leave_type} = context

    Enum.each([:pending, :cancelled], fn status ->
      Fixtures.leave_request(%{
        person_id: person.id,
        status: status,
        days: [entry(leave_type, @friday)]
      })
    end)

    taken(context)

    assert Enum.map(Leave.days_taken(person, @friday), & &1.date) == [@thursday]
  end

  test "balance entries come back oldest first, up to the date asked about", context do
    %{person: person, leave_type: leave_type, admin: admin} = context
    base = %{leave_type_id: leave_type.id}

    {:ok, _opening} =
      Leave.create_balance_entry(
        person,
        admin,
        Map.merge(base, %{date: ~D[2024-01-01], kind: :opening_balance, amount: "40"})
      )

    {:ok, _adjustment} =
      Leave.create_balance_entry(
        person,
        admin,
        Map.merge(base, %{
          date: ~D[2024-06-01],
          kind: :adjustment,
          amount: "-4",
          reason: "Duplicated on import"
        })
      )

    {:ok, _later} =
      Leave.create_balance_entry(
        person,
        admin,
        Map.merge(base, %{date: ~D[2025-01-01], kind: :opening_balance, amount: "8"})
      )

    entries = Leave.balance_entries(person, ~D[2024-12-31])

    assert Enum.map(entries, & &1.kind) == [:opening_balance, :adjustment]
  end

  test "a working day carries the hours the person works on it", context do
    assert Leave.working_days(context.person, Date.range(@thursday, @saturday)) == [
             {@thursday, Decimal.new("8.00")},
             {@friday, Decimal.new("8.00")}
           ]
  end
end
