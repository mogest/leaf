defmodule Leaf.PeopleTest do
  use Leaf.DataCase, async: true

  alias Leaf.Audit.Entry
  alias Leaf.Fixtures
  alias Leaf.People
  alias Leaf.People.Person

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

  test "a person cannot report to themselves", %{person: person} do
    changeset = Person.changeset(person, %{manager_id: person.id})

    assert errors_on(changeset).manager_id == ["cannot be the person themselves"]

    manager = Fixtures.person(%{organisation_id: person.organisation_id})

    assert Person.changeset(person, %{manager_id: manager.id}).valid?
  end

  test "the policy a person is on comes back as the id in force over each span", %{
    person: person,
    organisation: organisation
  } do
    first = Fixtures.leave_policy(%{organisation_id: organisation.id})
    second = Fixtures.leave_policy(%{organisation_id: organisation.id, name: "Hybrid contractor"})
    Fixtures.policy_assignment(%{person_id: person.id, leave_policy_id: first.id})

    Fixtures.policy_assignment(%{
      person_id: person.id,
      leave_policy_id: second.id,
      effective_from: ~D[2026-01-01]
    })

    assert People.leave_policy_segments(person, Date.range(~D[2025-12-30], ~D[2026-01-02])) == [
             {Date.range(~D[2025-12-30], ~D[2025-12-31]), first.id},
             {Date.range(~D[2026-01-01], ~D[2026-01-02]), second.id}
           ]
  end

  test "a policy assignment is corrected in place, and removing one lets the previous run on",
       context do
    %{person: person, organisation: organisation} = context
    colleague = Fixtures.person(%{organisation_id: organisation.id})
    first = Fixtures.leave_policy(%{organisation_id: organisation.id})
    second = Fixtures.leave_policy(%{organisation_id: organisation.id, name: "Hybrid contractor"})
    Fixtures.policy_assignment(%{person_id: person.id, leave_policy_id: first.id})

    moved =
      Fixtures.policy_assignment(%{
        person_id: person.id,
        leave_policy_id: second.id,
        effective_from: ~D[2026-01-01]
      })

    assert {:ok, corrected} =
             People.update_policy_assignment(moved, nil, %{
               effective_from: ~D[2026-02-01],
               person_id: colleague.id
             })

    assert corrected.person_id == person.id

    assert People.leave_policy_segments(person, Date.range(~D[2026-01-15], ~D[2026-02-15])) == [
             {Date.range(~D[2026-01-15], ~D[2026-01-31]), first.id},
             {Date.range(~D[2026-02-01], ~D[2026-02-15]), second.id}
           ]

    assert {:ok, _removed} = People.delete_policy_assignment(corrected, nil)

    assert People.leave_policy_segments(person, Date.range(~D[2026-02-01], ~D[2026-02-15])) == [
             {Date.range(~D[2026-02-01], ~D[2026-02-15]), first.id}
           ]
  end

  test "so does the calendar a person is on, until an assignment is removed", context do
    %{person: person, organisation: organisation} = context
    calendar = Fixtures.calendar(%{organisation_id: organisation.id})

    other =
      Fixtures.calendar(%{
        organisation_id: organisation.id,
        name: "Spain",
        country_code: "ES",
        time_zone: "Europe/Madrid"
      })

    Fixtures.public_holiday(%{calendar_id: calendar.id, date: ~D[2026-01-02], name: "Day after"})
    Fixtures.public_holiday(%{calendar_id: other.id, date: ~D[2026-01-06], name: "Reyes"})
    Fixtures.calendar_assignment(%{person_id: person.id, calendar_id: calendar.id})

    moved =
      Fixtures.calendar_assignment(%{
        person_id: person.id,
        calendar_id: other.id,
        effective_from: ~D[2026-01-01]
      })

    january = Date.range(~D[2026-01-01], ~D[2026-01-31])

    assert Enum.map(People.public_holidays(person, january), & &1.name) == ["Reyes"]
    assert {:ok, _removed} = People.delete_calendar_assignment(moved, nil)
    assert Enum.map(People.public_holidays(person, january), & &1.name) == ["Day after"]
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

  test "the holidays a person observes follow the calendar in force", context do
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

    Fixtures.calendar_assignment(%{
      person_id: context.person.id,
      calendar_id: spain.id,
      effective_from: ~D[2026-07-01]
    })

    observed = People.public_holidays(context.person, Date.range(~D[2026-01-01], ~D[2026-08-31]))

    assert Enum.map(observed, & &1.name) == ["King's", "Asunción"]
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
