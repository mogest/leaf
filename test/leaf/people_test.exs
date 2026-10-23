defmodule Leaf.PeopleTest do
  use Leaf.DataCase, async: true

  alias Leaf.Audit.Entry
  alias Leaf.Fixtures
  alias Leaf.People

  setup do
    organisation = Fixtures.organisation()
    person = Fixtures.person(%{organisation_id: organisation.id})

    %{organisation: organisation, person: person}
  end

  defp part_time(person) do
    Fixtures.work_pattern(%{
      person_id: person.id,
      effective_from: ~D[2026-01-01],
      monday_hours: "9",
      tuesday_hours: "9",
      wednesday_hours: "4",
      thursday_hours: "0",
      friday_hours: "0"
    })
  end

  defp ids(segments), do: Enum.map(segments, fn {span, row} -> {span, row.id} end)

  defp names(tree), do: Enum.map(tree, fn {person, reports} -> {person.name, names(reports)} end)

  test "an email address is the same address whatever case it was typed in", context do
    %{organisation: organisation} = context

    assert {:ok, person} =
             People.create_person(organisation, nil, %{
               name: "Wren Okafor",
               email: "Wren.Okafor@Example.test",
               role: :member,
               employment_start_date: ~D[2026-01-05]
             })

    assert person.email == "wren.okafor@example.test"

    assert {:error, changeset} =
             People.create_person(organisation, nil, %{
               name: "Wren Okafor",
               email: "WREN.OKAFOR@example.test",
               role: :member,
               employment_start_date: ~D[2026-01-05]
             })

    assert errors_on(changeset).email == ["has already been taken"]
  end

  test "an employee number names one person in an organisation", context do
    %{organisation: organisation, person: person} = context
    other = Fixtures.person(%{organisation_id: organisation.id})
    elsewhere = Fixtures.person(%{organisation_id: Fixtures.organisation().id})

    assert {:ok, _person} = People.update_person(person, nil, %{employee_number: "1001"})
    assert {:ok, _person} = People.update_person(elsewhere, nil, %{employee_number: "1001"})
    assert {:error, changeset} = People.update_person(other, nil, %{employee_number: "1001"})
    assert errors_on(changeset).employee_number == ["has already been taken"]
  end

  test "a work pattern applies until the next one supersedes it", %{person: person} do
    full_time = Fixtures.work_pattern(%{person_id: person.id})
    part_time = part_time(person)

    segments = People.work_pattern_segments(person, Date.range(~D[2025-06-01], ~D[2026-06-30]))

    assert ids(segments) == [
             {Date.range(~D[2025-06-01], ~D[2025-12-31]), full_time.id},
             {Date.range(~D[2026-01-01], ~D[2026-06-30]), part_time.id}
           ]

    assert {:ok, %{id: id}} = People.fetch_work_pattern_on(person, ~D[2025-12-31])
    assert id == full_time.id
    assert {:ok, %{id: id}} = People.fetch_work_pattern_on(person, ~D[2026-01-01])
    assert id == part_time.id
  end

  test "a work pattern cannot work negative hours, or more than a day holds", %{person: person} do
    attrs = %{
      effective_from: ~D[2026-01-01],
      monday_hours: "-1",
      tuesday_hours: "25",
      wednesday_hours: "8",
      thursday_hours: "8",
      friday_hours: "8",
      saturday_hours: "0",
      sunday_hours: "0"
    }

    assert {:error, changeset} = People.create_work_pattern(person, nil, attrs)
    assert errors_on(changeset).monday_hours == ["must be greater than or equal to 0"]
    assert errors_on(changeset).tuesday_hours == ["must be less than or equal to 24"]
  end

  test "a work pattern is corrected in place, and cannot be moved to somebody else", context do
    %{person: person, organisation: organisation} = context
    admin = Fixtures.person(%{organisation_id: organisation.id, role: :admin})
    colleague = Fixtures.person(%{organisation_id: organisation.id})
    pattern = part_time(person)

    assert {:ok, corrected} =
             People.update_work_pattern(pattern, admin, %{
               wednesday_hours: "9",
               person_id: colleague.id
             })

    assert corrected.person_id == person.id
    assert Decimal.equal?(People.weekly_hours(corrected), "27")

    assert [%{action: "work_pattern.updated", subject_person_id: subject, changes: changes}] =
             Repo.all(Entry)

    assert subject == person.id
    assert changes["wednesday_hours"] == %{"from" => "4.00", "to" => "9.00"}
  end

  test "removing a work pattern lets the one before it run on", context do
    %{person: person, organisation: organisation} = context
    admin = Fixtures.person(%{organisation_id: organisation.id, role: :admin})
    full_time = Fixtures.work_pattern(%{person_id: person.id})
    mistake = part_time(person)

    assert {:ok, _removed} = People.delete_work_pattern(mistake, admin)

    assert {:ok, %{id: id}} = People.fetch_work_pattern_on(person, ~D[2026-06-01])
    assert id == full_time.id
  end

  test "nothing applies before the first work pattern takes effect", %{person: person} do
    Fixtures.work_pattern(%{person_id: person.id})

    assert People.fetch_work_pattern_on(person, ~D[2024-01-01]) == :error
    assert People.work_pattern_segments(person, Date.range(~D[2024-01-01], ~D[2024-02-01])) == []
  end

  test "a pattern gives the hours worked on a date and the week they add up to", %{
    person: person,
    organisation: organisation
  } do
    part_time = part_time(person)

    assert {:ok, pattern} = People.fetch_work_pattern_on(person, ~D[2026-03-01])
    assert pattern.id == part_time.id
    assert Decimal.equal?(People.hours_on(pattern, ~D[2026-01-05]), "9")
    assert Decimal.equal?(People.hours_on(pattern, ~D[2026-01-07]), "4")
    assert Decimal.equal?(People.hours_on(pattern, ~D[2026-01-03]), "0")
    assert People.working_day?(pattern, ~D[2026-01-05])
    refute People.working_day?(pattern, ~D[2026-01-03])
    assert Decimal.equal?(People.weekly_hours(pattern), "22")
    assert Decimal.equal?(People.fte(pattern, organisation.full_time_week_hours), "0.55")
  end

  test "a change to a person is recorded against them", %{person: person} do
    manager = Fixtures.person(%{organisation_id: person.organisation_id})

    assert {:ok, reporting} = People.update_person(person, nil, %{manager_id: manager.id})
    assert reporting.manager_id == manager.id
    assert [%{action: "person.updated", subject_person_id: subject}] = Repo.all(Entry)
    assert subject == person.id
  end

  test "nobody can report to themselves, or to anyone under them however far down", %{person: rae} do
    bo = Fixtures.person(%{organisation_id: rae.organisation_id, manager_id: rae.id})
    ada = Fixtures.person(%{organisation_id: rae.organisation_id, manager_id: bo.id})

    for manager <- [rae, bo, ada] do
      assert {:error, changeset} = People.update_person(rae, nil, %{manager_id: manager.id})
      assert errors_on(changeset).manager_id == ["already reports to them"]
    end
  end

  test "the last administrator not archived can neither step down nor be archived",
       %{organisation: organisation} do
    kit = Fixtures.person(%{organisation_id: organisation.id, role: :admin})
    Fixtures.person(%{organisation_id: Fixtures.organisation().id, role: :admin})
    archived = Fixtures.person(%{organisation_id: organisation.id, role: :admin})
    {:ok, _archived} = People.archive_person(archived, nil)

    assert {:error, changeset} = People.update_person(kit, nil, %{role: :member})
    assert errors_on(changeset).role == ["nobody else administers the organisation"]
    assert {:error, changeset} = People.archive_person(kit, nil)
    assert errors_on(changeset).archived_at == ["nobody else administers the organisation"]

    Fixtures.person(%{organisation_id: organisation.id, role: :admin})
    assert {:ok, %{role: :member}} = People.update_person(kit, nil, %{role: :member})
  end

  test "neither employment date may move past approved or pending leave, only past declined or cancelled",
       %{person: person} do
    leave_type = Fixtures.leave_type(%{organisation_id: person.organisation_id})

    for {status, dates} <- [
          approved: [~D[2027-01-11], ~D[2027-01-15]],
          pending: [~D[2027-02-02]],
          declined: [~D[2027-03-01]],
          cancelled: [~D[2027-03-02]]
        ] do
      days =
        Enum.map(dates, &%{leave_type_id: leave_type.id, date: &1, amount: "8", unit: :hours})

      Fixtures.leave_request(%{person_id: person.id, status: status, days: days})
    end

    assert {:error, ending} =
             People.update_person(person, nil, %{employment_end_date: ~D[2027-01-10]})

    assert errors_on(ending).employment_end_date == [
             "is before approved leave on 11 – 15 January 2027, pending leave on 2 February 2027"
           ]

    assert {:error, starting} =
             People.update_person(person, nil, %{employment_start_date: ~D[2027-02-01]})

    assert errors_on(starting).employment_start_date == [
             "is after approved leave on 11 – 15 January 2027"
           ]

    assert {:ok, _left} =
             People.update_person(person, nil, %{employment_end_date: ~D[2027-02-02]})
  end

  test "an archived person is on no list but everybody, and their email and number are free again",
       context do
    %{organisation: organisation, person: rae} = context
    {:ok, rae} = People.update_person(rae, nil, %{employee_number: "1001"})

    assert {:ok, archived} = People.archive_person(rae, nil)
    assert {:ok, ^archived} = People.archive_person(rae, nil)
    assert archived.archived_at
    assert People.people(organisation.id) == []
    assert People.employed(organisation.id, Date.range(~D[2026-01-01], ~D[2026-12-31])) == []
    assert [%{name: "Rae Halloran"}] = People.everybody(organisation.id)
    assert People.fetch_person_by_email(rae.email) == :error
    assert People.fetch_unarchived_person(rae.id) == :error
    assert {:ok, %{archived_at: %DateTime{}}} = People.fetch_person(rae.id)

    wren = Fixtures.person(%{organisation_id: organisation.id, email: rae.email})
    assert {:error, changeset} = People.unarchive_person(archived, nil)
    assert errors_on(changeset) == %{email: ["has already been taken"]}

    {:ok, _wren} = People.archive_person(wren, nil)
    bo = Fixtures.person(%{organisation_id: organisation.id, employee_number: "1001"})
    assert {:error, changeset} = People.unarchive_person(archived, nil)
    assert errors_on(changeset) == %{employee_number: ["has already been taken"]}

    {:ok, _bo} = People.archive_person(bo, nil)
    assert {:ok, %{archived_at: nil}} = People.unarchive_person(archived, nil)

    assert ["person.archived", "person.unarchived", "person.updated"] =
             Repo.all(from entry in Entry, where: entry.subject_person_id == ^rae.id)
             |> Enum.map(& &1.action)
             |> Enum.sort()
  end

  test "archiving is refused while leave is pending or still to come, or anybody current reports to them",
       %{person: rae} do
    leave_type = Fixtures.leave_type(%{organisation_id: rae.organisation_id})

    for {status, date} <- [
          pending: ~D[2025-01-06],
          approved: ~D[2025-02-03],
          approved: ~D[2030-01-14],
          declined: ~D[2030-03-04]
        ] do
      days = [%{leave_type_id: leave_type.id, date: date, amount: "8", unit: :hours}]
      Fixtures.leave_request(%{person_id: rae.id, status: status, days: days})
    end

    Fixtures.person(%{organisation_id: rae.organisation_id, name: "Bo Ngata", manager_id: rae.id})

    ada =
      Fixtures.person(%{
        organisation_id: rae.organisation_id,
        name: "Ada Lindqvist",
        manager_id: rae.id
      })

    {:ok, _ada} = People.archive_person(ada, nil)

    assert {:error, changeset} = People.archive_person(rae, nil)

    assert errors_on(changeset).archived_at == [
             "they have pending leave on 6 January 2025, approved leave on 14 January 2030",
             "they manage Bo Ngata"
           ]
  end

  defp policy_ids(person, range) do
    person
    |> People.leave_policy_segments(range)
    |> Enum.map(fn {span, policy} -> {span, policy.id} end)
  end

  test "the policy a person is on comes back as the one in force over each span, until an assignment is removed",
       context do
    %{person: person, organisation: organisation} = context
    first = Fixtures.leave_policy(%{organisation_id: organisation.id})
    second = Fixtures.leave_policy(%{organisation_id: organisation.id, name: "Hybrid contractor"})
    Fixtures.policy_assignment(%{person_id: person.id, leave_policy_id: first.id})

    moved =
      Fixtures.policy_assignment(%{
        person_id: person.id,
        leave_policy_id: second.id,
        effective_from: ~D[2026-01-01]
      })

    span = Date.range(~D[2025-12-30], ~D[2026-01-02])

    assert policy_ids(person, span) == [
             {Date.range(~D[2025-12-30], ~D[2025-12-31]), first.id},
             {Date.range(~D[2026-01-01], ~D[2026-01-02]), second.id}
           ]

    assert {:ok, _removed} = People.delete_policy_assignment(moved, nil)
    assert policy_ids(person, span) == [{span, first.id}]
  end

  test "a second pattern, policy or calendar from the same date is refused on the date",
       context do
    %{person: person, organisation: organisation} = context
    policy = Fixtures.leave_policy(%{organisation_id: organisation.id})
    calendar = Fixtures.calendar(%{organisation_id: organisation.id})
    part_time(person)
    Fixtures.policy_assignment(%{person_id: person.id, leave_policy_id: policy.id})
    Fixtures.calendar_assignment(%{person_id: person.id, calendar_id: calendar.id})

    hours =
      Map.new(~w(monday tuesday wednesday thursday friday saturday sunday), &{"#{&1}_hours", "8"})

    assert {:error, patterned} =
             People.create_work_pattern(
               person,
               nil,
               Map.put(hours, "effective_from", "2026-01-01")
             )

    assert {:error, assigned} =
             People.create_policy_assignment(person, nil, %{
               "leave_policy_id" => policy.id,
               "effective_from" => "2024-03-04"
             })

    assert {:error, placed} =
             People.create_calendar_assignment(person, nil, %{
               "calendar_id" => calendar.id,
               "effective_from" => "2024-03-04"
             })

    for changeset <- [patterned, assigned, placed] do
      assert errors_on(changeset).effective_from == ["has already been taken"]
    end
  end

  test "everyone in an organisation comes back by name", context do
    Fixtures.person(%{organisation_id: context.organisation.id, name: "Bo Ngata"})
    elsewhere = Fixtures.organisation(%{name: "Kowhai Works"})
    Fixtures.person(%{organisation_id: elsewhere.id, name: "Ada Lindqvist"})

    assert Enum.map(People.people(context.organisation.id), & &1.name) == [
             "Bo Ngata",
             "Rae Halloran"
           ]
  end

  test "a manager oversees their reports, an administrator everyone, anybody else nobody",
       context do
    %{organisation: organisation, person: manager} = context
    admin = Fixtures.person(%{organisation_id: organisation.id, name: "Kit Rua", role: :admin})

    Fixtures.person(%{
      organisation_id: organisation.id,
      name: "Ines Vasquez",
      manager_id: manager.id
    })

    report =
      Fixtures.person(%{
        organisation_id: organisation.id,
        name: "Bo Ngata",
        manager_id: manager.id
      })

    nobody =
      Fixtures.person(%{
        organisation_id: organisation.id,
        name: "Ada Lindqvist",
        manager_id: report.id
      })

    assert Enum.map(People.overseen(manager), & &1.name) == ["Bo Ngata", "Ines Vasquez"]

    assert Enum.map(People.overseen(admin), & &1.name) ==
             ["Ada Lindqvist", "Bo Ngata", "Ines Vasquez", "Kit Rua", "Rae Halloran"]

    assert People.overseen(nobody) == []
  end

  test "the chart puts everyone employed under their manager, once each", context do
    %{organisation: organisation, person: rae} = context

    gone =
      Fixtures.person(%{
        organisation_id: organisation.id,
        name: "Tama Reti",
        employment_end_date: ~D[2025-06-30]
      })

    Fixtures.person(%{
      organisation_id: organisation.id,
      name: "Ines Vasquez",
      manager_id: gone.id
    })

    bo =
      Fixtures.person(%{organisation_id: organisation.id, name: "Bo Ngata", manager_id: rae.id})

    Fixtures.person(%{organisation_id: organisation.id, name: "Ada Lindqvist", manager_id: bo.id})

    assert names(People.chart(organisation.id, ~D[2026-06-01])) == [
             {"Ines Vasquez", []},
             {"Rae Halloran", [{"Bo Ngata", [{"Ada Lindqvist", []}]}]}
           ]
  end

  test "the holidays a person observes follow the calendar in force, until an assignment is removed",
       context do
    nz = Fixtures.calendar(%{organisation_id: context.organisation.id})

    spain =
      Fixtures.calendar(%{
        organisation_id: context.organisation.id,
        name: "Spain",
        country_code: "ES",
        time_zone: "Europe/Madrid"
      })

    Fixtures.public_holiday(%{calendar_id: nz.id, date: ~D[2026-06-01], name: "King's"})

    Fixtures.public_holiday(%{
      calendar_id: spain.id,
      date: ~D[2026-08-15],
      name: "Asunción"
    })

    Fixtures.public_holiday(%{
      calendar_id: spain.id,
      date: ~D[2026-12-25],
      name: "Navidad"
    })

    Fixtures.calendar_assignment(%{
      person_id: context.person.id,
      calendar_id: nz.id,
      effective_from: ~D[2026-01-01]
    })

    moved =
      Fixtures.calendar_assignment(%{
        person_id: context.person.id,
        calendar_id: spain.id,
        effective_from: ~D[2026-07-01]
      })

    span = Date.range(~D[2026-01-01], ~D[2026-08-31])

    assert Enum.map(People.public_holidays(context.person, span), & &1.name) == [
             "King's",
             "Asunción"
           ]

    assert {:ok, _removed} = People.delete_calendar_assignment(moved, nil)
    assert Enum.map(People.public_holidays(context.person, span), & &1.name) == ["King's"]
  end

  test "a weekend holiday moves to its weekday only for somebody who does not work the day it falls",
       context do
    calendar = Fixtures.calendar(%{organisation_id: context.organisation.id})

    Fixtures.public_holiday(%{
      calendar_id: calendar.id,
      date: ~D[2027-12-25],
      observed_on: ~D[2027-12-27],
      name: "Christmas Day"
    })

    Fixtures.public_holiday(%{
      calendar_id: calendar.id,
      date: ~D[2027-12-26],
      observed_on: ~D[2027-12-28],
      name: "Boxing Day"
    })

    saturday_worker = Fixtures.person(%{organisation_id: context.organisation.id})

    for person <- [context.person, saturday_worker] do
      Fixtures.calendar_assignment(%{person_id: person.id, calendar_id: calendar.id})
    end

    Fixtures.work_pattern(%{person_id: context.person.id})
    Fixtures.work_pattern(%{person_id: saturday_worker.id, saturday_hours: "8"})

    week = Date.range(~D[2027-12-25], ~D[2027-12-31])
    taken = &(&1 |> People.public_holidays(week) |> Enum.map(fn holiday -> holiday.date end))

    assert taken.(context.person) == [~D[2027-12-27], ~D[2027-12-28]]
    assert taken.(saturday_worker) == [~D[2027-12-25], ~D[2027-12-28]]

    after_christmas = Date.range(~D[2027-12-27], ~D[2027-12-31])

    assert Enum.map(People.public_holidays(saturday_worker, after_christmas), & &1.name) == [
             "Boxing Day"
           ]
  end

  test "a stretch on no calendar is a hole in the record where the whole share is counted",
       context do
    nz = Fixtures.calendar(%{organisation_id: context.organisation.id})

    Fixtures.calendar_assignment(%{
      person_id: context.person.id,
      calendar_id: nz.id,
      effective_from: ~D[2026-02-01]
    })

    year = Date.range(~D[2026-01-01], ~D[2026-12-31])

    assert People.public_holidays(context.person, year) == []

    assert_raise RuntimeError, ~r/no calendar in force/, fn ->
      People.public_holidays!(context.person, year)
    end
  end

  test "where somebody is is what says what day it is for them", context do
    # Twenty-five hours apart, so no instant finds the two of them on the same date.
    east =
      Fixtures.calendar(%{
        organisation_id: context.organisation.id,
        name: "Kiribati",
        country_code: "KI",
        time_zone: "Pacific/Kiritimati"
      })

    west =
      Fixtures.calendar(%{
        organisation_id: context.organisation.id,
        name: "Niue",
        country_code: "NU",
        time_zone: "Pacific/Niue"
      })

    other = Fixtures.person(%{organisation_id: context.organisation.id, name: "Bo Ngata"})

    assert People.time_zone(context.person) == "Etc/UTC"

    Fixtures.calendar_assignment(%{person_id: context.person.id, calendar_id: east.id})
    Fixtures.calendar_assignment(%{person_id: other.id, calendar_id: west.id})

    assert People.time_zone(context.person) == "Pacific/Kiritimati"
    assert People.today(context.person) != People.today(other)
  end
end
