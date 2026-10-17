defmodule Leaf.AuditTest do
  use Leaf.DataCase, async: true

  alias Leaf.Audit
  alias Leaf.Audit.Entry
  alias Leaf.Fixtures
  alias Leaf.Leave.Request
  alias Leaf.Org
  alias Leaf.Org.PublicHoliday
  alias Leaf.People.Person
  alias Leaf.Policies

  setup do
    organisation = Fixtures.organisation()
    actor = Fixtures.person(%{organisation_id: organisation.id, role: :admin})
    person = Fixtures.person(%{organisation_id: organisation.id})

    %{organisation: organisation, actor: actor, person: person}
  end

  test "an insert is recorded against the row it created, with what it set and the ids of rows nested in it",
       context do
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
    assert [%{"id" => id, "amount" => "8.00", "unit" => "hours"}] = entry.changes["days"]["to"]
    assert [%{id: ^id}] = filed.days
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
    calendar = Fixtures.calendar(%{organisation_id: context.organisation.id})

    holiday =
      Fixtures.public_holiday(%{
        calendar_id: calendar.id,
        date: ~D[2026-06-19],
        name: "Entered twice"
      })

    assert {:ok, _removed} = Audit.delete(holiday, "public_holiday.deleted", context.actor)

    assert [%{changes: changes}] = Repo.all(Entry)
    assert changes["date"] == %{"from" => "2026-06-19", "to" => nil}
    assert changes["name"] == %{"from" => "Entered twice", "to" => nil}
    assert Repo.all(PublicHoliday) == []
  end

  test "a created row's entry names what it belongs to", %{
    organisation: organisation,
    actor: actor
  } do
    country = Fixtures.calendar(%{organisation_id: organisation.id})
    policy = Fixtures.leave_policy(%{organisation_id: organisation.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})

    assert {:ok, region} = Org.create_region(country, actor, %{name: "Canterbury"})

    assert {:ok, holiday} =
             Org.create_public_holiday(region, actor, %{name: "Show Day", date: ~D[2026-11-13]})

    assert {:ok, entitlement} =
             Policies.create_entitlement(policy, leave_type, actor, %{
               effective_from: ~D[2026-01-01],
               amount_source: :fixed,
               grant_amount: "160",
               grant_basis: :employment_date,
               grant_period: :year,
               grant_timing: :daily,
               pro_rated_by_fte: true,
               expiry_rule: :never
             })

    changes = Map.new(Repo.all(Entry), &{&1.entity_id, &1.changes})
    assert changes[region.id]["parent_id"] == %{"from" => nil, "to" => country.id}
    assert changes[holiday.id]["calendar_id"] == %{"from" => nil, "to" => region.id}
    assert changes[entitlement.id]["leave_policy_id"] == %{"from" => nil, "to" => policy.id}
    assert changes[entitlement.id]["leave_type_id"] == %{"from" => nil, "to" => leave_type.id}
  end

  test "entries come a page at a time, newest first, narrowed to a person and to a day's end",
       context do
    stamp = fn at, about ->
      Repo.insert!(%Entry{
        action: "person.updated",
        entity_type: "people",
        entity_id: about,
        subject_person_id: about,
        changes: %{},
        inserted_at: at
      })
    end

    # 23:30 and 00:30 either side of midnight in Auckland, which is 13 hours ahead in October.
    late = stamp.(~U[2026-10-01 10:30:00.000000Z], context.person.id)
    next_day = stamp.(~U[2026-10-01 11:30:00.000000Z], context.person.id)
    earlier = stamp.(~U[2026-09-30 00:00:00.000000Z], context.actor.id)

    ids = fn filter -> Enum.map(Audit.page(filter, 1, 10).entries, & &1.id) end

    assert ids.([]) == [next_day.id, late.id, earlier.id]
    assert %{entries: [%{id: id}], page: 2, pages: 3} = Audit.page([], 2, 1)
    assert id == late.id
    assert %{page: 3} = Audit.page([], 9, 1)
    assert %{page: 1, pages: 1} = Audit.page([about: context.actor.id], -1, 1)
    assert ids.(about: context.person.id) == [next_day.id, late.id]
    assert ids.(through: ~D[2026-10-01], zone: "Pacific/Auckland") == [late.id, earlier.id]
  end

  test "a save that changed nothing is not recorded", context do
    %{actor: actor, person: person} = context

    assert {:ok, _unchanged} =
             person
             |> Person.changeset(%{name: person.name})
             |> Audit.write("person.updated", actor, person.id)

    assert Repo.all(Entry) == []
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
