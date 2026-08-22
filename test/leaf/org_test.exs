defmodule Leaf.OrgTest do
  use Leaf.DataCase, async: true

  alias Leaf.Audit.Entry
  alias Leaf.Fixtures
  alias Leaf.Org

  test "an organisation works a positive week, in a month of the year" do
    attrs = %{
      name: "Fernbank Collective",
      full_time_week_hours: "0",
      standard_day_hours: "8",
      year_start_month: 13,
      tracked_from: ~D[2024-01-01]
    }

    assert {:error, changeset} = Org.create_organisation(nil, attrs)
    assert errors_on(changeset).full_time_week_hours == ["must be greater than 0"]
    assert errors_on(changeset).year_start_month == ["is invalid"]
  end

  test "moving the date tracking started is recorded like any other change" do
    organisation = Fixtures.organisation()
    admin = Fixtures.person(%{organisation_id: organisation.id, role: :admin})

    assert {:ok, moved} =
             Org.update_organisation(organisation, admin, %{tracked_from: ~D[2025-04-01]})

    assert moved.tracked_from == ~D[2025-04-01]

    assert [%{action: "organisation.updated", subject_person_id: nil, changes: changes}] =
             Repo.all(Entry)

    assert changes["tracked_from"] == %{"from" => "2024-01-01", "to" => "2025-04-01"}
  end

  test "an organisation is found by id" do
    organisation = Fixtures.organisation()

    assert {:ok, found} = Org.fetch_organisation(organisation.id)
    assert found.id == organisation.id
    assert found.tracked_from == ~D[2024-01-01]
    assert Org.fetch_organisation(Ecto.UUID.generate()) == :error
  end

  test "a calendar gives up the holidays falling inside a range, in date order" do
    organisation = Fixtures.organisation()
    calendar = Fixtures.holiday_calendar(%{organisation_id: organisation.id})

    other =
      Fixtures.holiday_calendar(%{
        organisation_id: organisation.id,
        name: "Spain",
        country_code: "ES"
      })

    Fixtures.public_holiday(%{
      holiday_calendar_id: calendar.id,
      date: ~D[2026-02-06],
      name: "February holiday"
    })

    Fixtures.public_holiday(%{holiday_calendar_id: calendar.id, date: ~D[2026-01-01]})

    Fixtures.public_holiday(%{
      holiday_calendar_id: calendar.id,
      date: ~D[2026-04-03],
      name: "April holiday"
    })

    Fixtures.public_holiday(%{
      holiday_calendar_id: other.id,
      date: ~D[2026-01-06],
      name: "Epiphany"
    })

    holidays = Org.public_holidays(calendar.id, Date.range(~D[2026-01-01], ~D[2026-03-31]))

    assert Enum.map(holidays, & &1.date) == [~D[2026-01-01], ~D[2026-02-06]]
  end

  test "a calendar cannot hold the same date twice, so an allowance cannot double-count it" do
    organisation = Fixtures.organisation()
    calendar = Fixtures.holiday_calendar(%{organisation_id: organisation.id})
    Fixtures.public_holiday(%{holiday_calendar_id: calendar.id, date: ~D[2026-01-01]})

    attrs = %{date: ~D[2026-01-01], name: "New Year"}

    assert {:error, changeset} = Org.create_public_holiday(calendar, nil, attrs)
    assert errors_on(changeset).holiday_calendar_id == ["has already been taken"]
  end
end
