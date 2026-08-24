defmodule Leaf.OrgTest do
  use Leaf.DataCase, async: true

  alias Leaf.Audit.Entry
  alias Leaf.Fixtures
  alias Leaf.Org

  test "an organisation works a positive week, in a month of the year" do
    # Sub-cent rather than zero: the column rounds it to nothing, and a full-time week of nothing
    # divides by zero in every FTE on the site.
    attrs = %{
      name: "Fernbank Collective",
      full_time_week_hours: "0.001",
      standard_day_hours: "8",
      year_start_month: 13,
      tracked_from: ~D[2024-01-01]
    }

    assert {:error, changeset} = Org.create_organisation(nil, attrs)
    assert errors_on(changeset).full_time_week_hours == ["must be greater than 0"]
    assert errors_on(changeset).year_start_month == ["is invalid"]
  end

  test "an organisation cannot work more hours than a week or a day holds" do
    attrs = %{
      name: "Fernbank Collective",
      full_time_week_hours: "200",
      standard_day_hours: "1200000000",
      year_start_month: 4,
      tracked_from: ~D[2024-01-01]
    }

    assert {:error, changeset} = Org.create_organisation(nil, attrs)
    assert errors_on(changeset).full_time_week_hours == ["must be less than or equal to 168"]
    assert errors_on(changeset).standard_day_hours == ["must be less than or equal to 24"]
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

  test "a calendar gives up the holidays falling inside a range, its country's included" do
    organisation = Fixtures.organisation()
    calendar = Fixtures.calendar(%{organisation_id: organisation.id})

    other =
      Fixtures.calendar(%{
        organisation_id: organisation.id,
        name: "Spain",
        country_code: "ES",
        time_zone: "Europe/Madrid"
      })

    region =
      Fixtures.calendar(%{
        organisation_id: organisation.id,
        parent_id: calendar.id,
        name: "Wellington"
      })

    Fixtures.public_holiday(%{
      calendar_id: calendar.id,
      date: ~D[2026-02-06],
      name: "February holiday"
    })

    Fixtures.public_holiday(%{calendar_id: calendar.id, date: ~D[2026-01-01]})

    Fixtures.public_holiday(%{
      calendar_id: calendar.id,
      date: ~D[2026-04-03],
      name: "April holiday"
    })

    Fixtures.public_holiday(%{
      calendar_id: other.id,
      date: ~D[2026-01-06],
      name: "Epiphany"
    })

    Fixtures.public_holiday(%{
      calendar_id: region.id,
      date: ~D[2026-01-19],
      name: "Anniversary Day"
    })

    quarter = Date.range(~D[2026-01-01], ~D[2026-03-31])

    assert Enum.map(Org.observed_holidays(calendar.id, quarter), & &1.date) == [
             ~D[2026-01-01],
             ~D[2026-02-06]
           ]

    assert Enum.map(Org.observed_holidays(region.id, quarter), & &1.date) == [
             ~D[2026-01-01],
             ~D[2026-01-19],
             ~D[2026-02-06]
           ]

    assert Enum.map(Org.public_holidays(region.id), & &1.date) == [~D[2026-01-19]]
  end

  test "a day both a region and its country keep is observed once, under the region's name for it" do
    organisation = Fixtures.organisation()
    country = Fixtures.calendar(%{organisation_id: organisation.id})

    region =
      Fixtures.calendar(%{
        organisation_id: organisation.id,
        parent_id: country.id,
        name: "Wellington"
      })

    Fixtures.public_holiday(%{
      calendar_id: country.id,
      date: ~D[2026-02-06],
      name: "Waitangi Day"
    })

    Fixtures.public_holiday(%{
      calendar_id: region.id,
      date: ~D[2026-02-06],
      name: "Waitangi here"
    })

    observed = Org.observed_holidays(region.id, Date.range(~D[2026-01-01], ~D[2026-12-31]))

    assert Enum.map(observed, & &1.name) == ["Waitangi here"]
  end

  test "a calendar will not take a zone the database cannot read" do
    organisation = Fixtures.organisation()
    attrs = %{name: "Nowhere", country_code: "NZ", time_zone: "Pacific/Nowhere"}

    assert {:error, changeset} = Org.create_calendar(organisation, nil, attrs)
    assert errors_on(changeset).time_zone == ["is not a time zone"]
  end

  test "a calendar is offered the zones of its country, and all of them where it has no country" do
    assert Org.time_zones("NZ") == ["Pacific/Auckland", "Pacific/Chatham"]
    assert Org.time_zones("nz") == Org.time_zones("NZ")
    assert Org.time_zones("ZZ") == Org.time_zones(nil)
    assert "Etc/UTC" in Org.time_zones(nil)
  end

  test "a calendar cannot hold the same date twice, so an allowance cannot double-count it" do
    organisation = Fixtures.organisation()
    calendar = Fixtures.calendar(%{organisation_id: organisation.id})
    Fixtures.public_holiday(%{calendar_id: calendar.id, date: ~D[2026-01-01]})

    attrs = %{date: ~D[2026-01-01], name: "New Year"}

    assert {:error, changeset} = Org.create_public_holiday(calendar, nil, attrs)
    assert errors_on(changeset).calendar_id == ["has already been taken"]
  end
end
