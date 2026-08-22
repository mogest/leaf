defmodule Leaf.AuditTest do
  use Leaf.DataCase, async: true

  alias Leaf.Audit
  alias Leaf.Audit.Entry
  alias Leaf.Fixtures
  alias Leaf.Leave.Request
  alias Leaf.Org.PublicHoliday
  alias Leaf.People.Person

  setup do
    organisation = Fixtures.organisation()
    actor = Fixtures.person(%{organisation_id: organisation.id, role: :admin})
    person = Fixtures.person(%{organisation_id: organisation.id})

    %{organisation: organisation, actor: actor, person: person}
  end

  test "an insert is recorded against the row it created, with what it set", context do
    %{actor: actor, person: person} = context
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})

    request = %Request{person_id: person.id, submitted_by_id: person.id, status: :pending}

    days = [
      %{
        leave_type_id: leave_type.id,
        date: ~D[2026-08-20],
        amount: "8",
        unit: :hours,
        hours_in_day: "8"
      }
    ]

    assert {:ok, filed} =
             request
             |> Request.changeset(%{days: days, note: "Away"})
             |> Audit.write("leave_request.requested", actor, person.id)

    assert [entry] = Repo.all(Entry)
    assert entry.entity_type == "leave_requests"
    assert entry.entity_id == filed.id
    assert entry.actor_id == actor.id
    assert entry.changes["note"] == %{"from" => nil, "to" => "Away"}
    assert [%{"amount" => "8", "unit" => "hours"}] = entry.changes["days"]["to"]
  end

  test "an update is recorded with the value it replaced", context do
    %{actor: actor, person: person} = context

    assert {:ok, _renamed} =
             person
             |> Person.changeset(%{name: "Wren Okafor"})
             |> Audit.write("person.updated", actor, person.id)

    assert [%{changes: changes}] = Repo.all(Entry)
    assert changes["name"] == %{"from" => person.name, "to" => "Wren Okafor"}
  end

  test "a deleted row survives in what recorded it", context do
    calendar = Fixtures.holiday_calendar(%{organisation_id: context.organisation.id})

    holiday =
      Fixtures.public_holiday(%{
        holiday_calendar_id: calendar.id,
        date: ~D[2026-06-19],
        name: "Entered twice"
      })

    assert {:ok, _removed} = Audit.delete(holiday, "public_holiday.deleted", context.actor)

    assert [%{changes: changes}] = Repo.all(Entry)
    assert changes["date"] == %{"from" => "2026-06-19", "to" => nil}
    assert changes["name"] == %{"from" => "Entered twice", "to" => nil}
    assert Repo.all(PublicHoliday) == []
  end

  test "a refused change is not recorded", context do
    %{actor: actor, person: person} = context

    assert {:error, changeset} =
             person
             |> Person.changeset(%{email: "not an email"})
             |> Audit.write("person.updated", actor, person.id)

    assert errors_on(changeset).email == ["has invalid format"]
    assert Repo.all(Entry) == []
  end
end
