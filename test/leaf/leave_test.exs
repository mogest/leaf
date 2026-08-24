defmodule Leaf.LeaveTest do
  use Leaf.DataCase, async: true

  alias Leaf.Audit.Entry
  alias Leaf.Fixtures
  alias Leaf.Leave
  alias Leaf.Policies

  @thursday ~D[2026-08-20]
  @friday ~D[2026-08-21]
  @saturday ~D[2026-08-22]
  @ahead ~D[2026-12-01]

  setup do
    organisation = Fixtures.organisation()
    manager = Fixtures.person(%{organisation_id: organisation.id, name: "Ines Vasquez"})

    admin =
      Fixtures.person(%{organisation_id: organisation.id, name: "Toma Ferrer", role: :admin})

    person =
      Fixtures.person(%{organisation_id: organisation.id, manager_id: manager.id})

    Fixtures.work_pattern(%{person_id: person.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})

    entitlement =
      Fixtures.offering(%{
        person_id: person.id,
        organisation_id: organisation.id,
        leave_type_id: leave_type.id
      })

    %{
      organisation: organisation,
      person: person,
      manager: manager,
      admin: admin,
      leave_type: leave_type,
      entitlement: entitlement
    }
  end

  defp entry(leave_type, date, attrs \\ %{}) do
    Map.merge(%{leave_type_id: leave_type.id, date: date, amount: "8", unit: :hours}, attrs)
  end

  defp file(context, dates, attrs \\ %{}) do
    days = Enum.map(dates, &entry(context.leave_type, &1, attrs))

    Leave.request(context.person, context.person, %{days: days, note: "Away"})
  end

  # Deciding a request turns on the reporting line, which only the read hands back.
  defp reload(request) do
    {:ok, reloaded} = Leave.fetch_request(request.id)
    reloaded
  end

  defp observes(context, holiday, name \\ "New Year's Day") do
    calendar = Fixtures.calendar(%{organisation_id: context.organisation.id})
    Fixtures.public_holiday(%{calendar_id: calendar.id, date: holiday, name: name})

    Fixtures.calendar_assignment(%{
      person_id: context.person.id,
      calendar_id: calendar.id
    })
  end

  # Public holidays are credited as a share of a leave type of their own, so this goes on the policy
  # the person is already on rather than replacing the terms their annual leave is offered under.
  defp crediting_holidays(context) do
    leave_type =
      Fixtures.leave_type(%{
        organisation_id: context.organisation.id,
        name: "Public holidays",
        position: 3
      })

    Fixtures.policy_entitlement(%{
      leave_policy_id: context.entitlement.leave_policy_id,
      leave_type_id: leave_type.id,
      amount_source: :public_holidays,
      grant_amount: nil
    })
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

    assert Leave.working_days(context.person, Date.range(@thursday, @saturday)) ==
             [{@thursday, Decimal.new("8.00")}]

    assert {:error, changeset} = file(context, [@friday])
    assert [%{date: ["is not a working day"]}] = errors_on(changeset).days
  end

  test "a public holiday is an ordinary day where the policy credits it instead", context do
    observes(context, @friday)
    crediting_holidays(context)

    assert Leave.working_days(context.person, Date.range(@thursday, @saturday)) ==
             [{@thursday, Decimal.new("8.00")}, {@friday, Decimal.new("8.00")}]

    assert {:ok, %{status: :pending}} = file(context, [@friday])
  end

  test "leave cannot be filed on a date before the person's first work pattern", context do
    assert {:error, changeset} = file(context, [~D[2024-02-01]])
    assert [%{date: ["is before the first work pattern on record"]}] = errors_on(changeset).days
    assert Repo.all(Entry) == []
  end

  # Filing a day needs the record to reach back over it in both senses: hours to measure it by, and
  # a policy offering its leave type on the date.
  test "a pattern and a policy reaching back over the date are what make it filable", context do
    Fixtures.work_pattern(%{person_id: context.person.id, effective_from: ~D[2024-01-01]})

    Fixtures.policy_assignment(%{
      person_id: context.person.id,
      leave_policy_id: context.entitlement.leave_policy_id,
      effective_from: ~D[2024-01-01]
    })

    {:ok, _reaching} =
      Policies.update_entitlement(context.entitlement, nil, %{effective_from: ~D[2024-01-01]})

    assert {:ok, %{status: :pending}} = file(context, [~D[2024-02-01]])
  end

  test "leave cannot be filed against a leave type nobody offers the person", context do
    other = Fixtures.organisation(%{name: "Harbourline Trust"})
    theirs = Fixtures.leave_type(%{organisation_id: other.id})

    assert {:error, changeset} =
             Leave.request(context.person, context.person, %{days: [entry(theirs, @friday)]})

    assert errors_on(changeset).days == ["hold a leave type that was not on offer on its date"]
    assert Repo.all(Entry) == []
  end

  test "withdrawing a leave type stops it being filed against, or amended into", context do
    {:ok, filed} = file(context, [@thursday])

    {:ok, _withdrawn} =
      Policies.update_leave_type(context.leave_type, context.admin, %{
        archived_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    assert {:error, filing} = file(context, [@friday])
    assert errors_on(filing).days == ["hold a leave type that was not on offer on its date"]

    assert {:error, amending} =
             Leave.amend(reload(filed), context.person, %{
               days: [entry(context.leave_type, @friday)]
             })

    assert errors_on(amending).days == ["hold a leave type that was not on offer on its date"]
  end

  test "leave cannot be filed on a date its entitlement no longer covers", context do
    {:ok, _closed} =
      Policies.update_entitlement(context.entitlement, nil, %{effective_to: @thursday})

    assert {:error, changeset} = file(context, [@friday])
    assert errors_on(changeset).days == ["hold a leave type that was not on offer on its date"]
    assert {:ok, %{status: :pending}} = file(context, [@thursday])
  end

  test "leave cannot be filed over a day already spoken for, decided or not", context do
    {:ok, filed} = file(context, [@thursday, @friday], %{amount: "1", unit: :days})

    assert {:error, changeset} = file(context, [@friday], %{amount: "1", unit: :days})
    assert errors_on(changeset).days == ["ask for more of a day than is left in it"]
    assert [%{action: "leave_request.requested"}] = Repo.all(Entry)

    {:ok, request} = Leave.fetch_request(filed.id)

    assert {:ok, _amended} =
             Leave.amend(request, context.person, %{
               days: [entry(context.leave_type, @friday, %{amount: "1", unit: :days})]
             })
  end

  test "a day holds its hours and no more, however many leave types share it", context do
    sick =
      Fixtures.leave_type(%{
        organisation_id: context.organisation.id,
        name: "Sick leave",
        position: 2
      })

    Fixtures.offering(%{
      leave_policy_id: context.entitlement.leave_policy_id,
      leave_type_id: sick.id
    })

    filing = fn leave_type, amount ->
      Leave.request(context.person, context.person, %{
        days: [entry(leave_type, @friday, %{amount: amount})]
      })
    end

    assert {:ok, _morning} = filing.(context.leave_type, "6")
    assert {:ok, _afternoon} = filing.(sick, "2")
    assert {:error, changeset} = filing.(sick, "0.5")

    assert errors_on(changeset).days == ["ask for more of a day than is left in it"]
  end

  test "a date is free again once the leave on it has been declined", context do
    {:ok, filed} = file(context, [@friday])
    {:ok, _declined} = filed |> reload() |> Leave.decline(context.manager)

    assert {:ok, %{status: :pending}} = file(context, [@friday])
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

  test "only approved leave counts as taken, whenever it falls", context do
    %{person: person, leave_type: leave_type} = context

    Enum.each([:pending, :cancelled], fn status ->
      Fixtures.leave_request(%{
        person_id: person.id,
        status: status,
        days: [entry(leave_type, @friday)]
      })
    end)

    Fixtures.leave_request(%{person_id: person.id, days: [entry(leave_type, @ahead)]})
    taken(context)

    assert Enum.map(Leave.days_approved(person), & &1.date) == [@thursday, @ahead]
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

  test "a person's requests come back with the leave furthest ahead first", context do
    {:ok, soonest} = file(context, [~D[2026-08-25]])
    {:ok, furthest} = file(context, [~D[2026-11-02]])
    {:ok, _declined} = soonest |> reload() |> Leave.decline(context.manager, "Too many away")

    other = Fixtures.person(%{organisation_id: context.organisation.id, name: "Bo Ngata"})
    Fixtures.leave_request(%{person_id: other.id, days: [entry(context.leave_type, @friday)]})

    assert [ahead, behind] = Leave.requests(context.person)
    assert ahead.id == furthest.id
    assert behind.id == soonest.id
    assert behind.status == :declined
    assert behind.reviewed_by.name == "Ines Vasquez"
    assert [%{date: ~D[2026-08-25]}] = behind.days
  end

  test "undecided requests come before decided ones, whenever the leave falls", context do
    {:ok, waiting} = file(context, [~D[2026-08-25]])
    {:ok, furthest} = file(context, [~D[2026-11-02]])
    {:ok, decided} = furthest |> reload() |> Leave.approve(context.manager)

    assert [first, second] = Leave.requests_undecided_first(context.person)
    assert first.id == waiting.id
    assert second.id == decided.id
  end

  test "a calendar lays a month out in weeks and marks what is on each day", context do
    observes(context, ~D[2026-08-26], "Labour Day")
    {:ok, _pending} = file(context, [@friday])
    {:ok, approving} = file(context, [@thursday])
    {:ok, _approved} = approving |> reload() |> Leave.approve(context.manager)

    assert [august] = Leave.calendar(context.person, Date.range(~D[2026-08-01], ~D[2026-08-31]))
    assert august.starts_on == ~D[2026-08-01]
    assert Enum.map(august.weeks, &length/1) == [7, 7, 7, 7, 7, 7]
    assert Enum.take(hd(august.weeks), 5) == [nil, nil, nil, nil, nil]

    days = august.weeks |> List.flatten() |> Enum.reject(&is_nil/1) |> Map.new(&{&1.date, &1})

    assert %{leave: :pending, working?: true} = days[@friday]
    assert %{leave: :approved, working?: true} = days[@thursday]
    assert %{holiday: "Labour Day", working?: false} = days[~D[2026-08-26]]
    assert %{leave: nil, holiday: nil, working?: false} = days[@saturday]
  end

  test "only leave somebody still holds shows within a range", context do
    {:ok, pending} = file(context, [@friday])
    {:ok, approving} = file(context, [~D[2026-08-24]])
    {:ok, _approved} = approving |> reload() |> Leave.approve(context.manager)
    {:ok, cancelling} = file(context, [~D[2026-08-26]])
    {:ok, _cancelled} = cancelling |> reload() |> Leave.cancel(context.manager)
    {:ok, _outside} = file(context, [~D[2026-09-30]])

    days = Leave.days_filed(context.person, Date.range(@thursday, ~D[2026-08-31]))

    assert Enum.map(days, & &1.date) == [~D[2026-08-21], ~D[2026-08-24]]
    assert Enum.map(days, & &1.leave_request.status) == [:pending, :approved]
    assert hd(days).leave_request.id == pending.id
  end

  describe "requestable/2" do
    setup context do
      policy_id = context.entitlement.leave_policy_id

      sick_leave =
        Fixtures.leave_type(%{
          organisation_id: context.organisation.id,
          name: "Sick leave",
          unit: :days,
          position: 2
        })

      {:ok, _closed} =
        Policies.update_entitlement(context.entitlement, nil, %{effective_to: ~D[2026-03-31]})

      Fixtures.policy_entitlement(%{leave_policy_id: policy_id, leave_type_id: sick_leave.id})

      %{policy_id: policy_id}
    end

    defp offered(person, first, last) do
      person |> Leave.requestable(Date.range(first, last)) |> Enum.map(& &1.name)
    end

    test "a closed entitlement still answers for the dates it covered", context do
      assert offered(context.person, ~D[2026-02-02], ~D[2026-02-06]) ==
               ["Annual leave", "Sick leave"]
    end

    test "and for none of the dates after it", context do
      assert offered(context.person, ~D[2026-04-01], ~D[2026-04-03]) == ["Sick leave"]
    end

    test "a type offered over part of a range is not offered over the range", context do
      assert offered(context.person, ~D[2026-03-30], ~D[2026-04-03]) == ["Sick leave"]
    end

    test "a type closed and offered again covers what the pair of them cover", context do
      Fixtures.policy_entitlement(%{
        leave_policy_id: context.policy_id,
        leave_type_id: context.leave_type.id,
        effective_from: ~D[2026-04-01]
      })

      assert offered(context.person, ~D[2026-03-30], ~D[2026-04-03]) ==
               ["Annual leave", "Sick leave"]
    end

    test "a range the person was on no policy over offers nothing", context do
      assert offered(context.person, ~D[2024-03-01], ~D[2024-03-06]) == []
    end
  end
end
