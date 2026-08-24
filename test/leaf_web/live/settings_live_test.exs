defmodule LeafWeb.SettingsLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Org
  alias Leaf.Policies

  setup %{conn: conn} do
    organisation = Fixtures.organisation()
    admin = Fixtures.person(%{organisation_id: organisation.id, name: "Kit Rua", role: :admin})

    %{conn: sign_in(conn, admin), organisation: organisation, admin: admin}
  end

  test "the organisation's own settings can be amended", context do
    {:ok, live, _html} = live(context.conn, ~p"/settings")

    live
    |> form("#organisation",
      organisation: %{
        "name" => "Fernbank",
        "full_time_week_hours" => "37.5",
        "standard_day_hours" => "7.5",
        "year_start_month" => "7",
        "tracked_from" => "2025-01-01"
      }
    )
    |> render_submit()

    {:ok, amended} = Org.fetch_organisation(context.organisation.id)

    assert amended.name == "Fernbank"
    assert amended.year_start_month == 7
    assert amended.tracked_from == ~D[2025-01-01]
  end

  test "a leave type can be added, amended and stopped from being offered", context do
    {:ok, live, _html} = live(context.conn, ~p"/settings/leave-types")

    live
    |> form("#new-leave-type",
      leave_type: %{"name" => "Study leave", "unit" => "days", "position" => "1"}
    )
    |> render_submit()

    assert [leave_type] = Policies.leave_types(context.organisation.id)
    assert leave_type.name == "Study leave"

    {:ok, live, _html} = live(context.conn, ~p"/settings/leave-types/#{leave_type}")
    live |> form("#leave-type", leave_type: %{"name" => "Study"}) |> render_submit()

    {:ok, _live, html} = live(context.conn, ~p"/settings/leave-types")
    assert html =~ "Study"

    {:ok, live, _html} = live(context.conn, ~p"/settings/leave-types/#{leave_type}")
    html = live |> element("button", "Stop offering it in new configuration") |> render_click()
    assert html =~ "Not offered in new configuration since"

    {:ok, archived} = Policies.fetch_leave_type(leave_type.id)
    assert archived.archived_at
  end

  test "a policy grants what its entitlements say, in words", context do
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})
    {:ok, live, _html} = live(context.conn, ~p"/settings/policies")

    live |> form("#new-policy", leave_policy: %{"name" => "NZ employee"}) |> render_submit()

    assert [policy] = Policies.leave_policies(context.organisation.id)

    {:ok, _live, html} = live(context.conn, ~p"/settings/policies/#{policy}")
    assert html =~ "This policy grants nothing yet."

    {:ok, live, _html} = live(context.conn, ~p"/settings/policies/#{policy}/entitlements/new")

    live
    |> form("#entitlement",
      policy_entitlement: %{
        "leave_type_id" => leave_type.id,
        "effective_from" => "2024-01-01",
        "amount_source" => "fixed",
        "grant_amount" => "160",
        "grant_period" => "year",
        "grant_basis" => "employment_date",
        "grant_timing" => "daily",
        "pro_rated_by_fte" => "true",
        "expiry_rule" => "never",
        "allow_negative" => "false"
      }
    )
    |> render_submit()

    {:ok, live, html} = live(context.conn, ~p"/settings/policies/#{policy}")

    assert html =~ "160 hours each year, reckoned from their start date, accruing day by day"
    assert html =~ "pro-rated by the hours they work"
    assert html =~ "Rolls over indefinitely"

    html = live |> element("button", "Remove") |> render_click()
    assert html =~ "This policy grants nothing yet."
  end

  test "an entitlement that grants nothing is refused a grant period", context do
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})

    {:ok, live, _html} = live(context.conn, ~p"/settings/policies/#{policy}/entitlements/new")

    html =
      live
      |> form("#entitlement",
        policy_entitlement: %{
          "leave_type_id" => leave_type.id,
          "effective_from" => "2024-01-01",
          "amount_source" => "none",
          "grant_period" => "year",
          "pro_rated_by_fte" => "false",
          "expiry_rule" => "never",
          "allow_negative" => "false"
        }
      )
      |> render_submit()

    assert html =~ "must be blank"
    assert Policies.entitlements(policy.id) == []
  end

  test "a calendar holds the holidays put on it, and lets one off again", context do
    {:ok, live, _html} = live(context.conn, ~p"/settings/calendars")

    live
    |> form("#new-calendar",
      calendar: %{
        "name" => "New Zealand",
        "country_code" => "NZ",
        "time_zone" => "Pacific/Auckland"
      }
    )
    |> render_submit()

    assert [calendar] = Org.calendars(context.organisation.id)

    {:ok, live, _html} = live(context.conn, ~p"/settings/calendars/#{calendar}")

    html =
      live
      |> form("#new-holiday", public_holiday: %{"date" => "2026-10-26", "name" => "Labour Day"})
      |> render_submit()

    assert html =~ "Labour Day"
    assert html =~ "26 October 2026"

    html = live |> element("button", "Remove") |> render_click()

    assert html =~ "No holidays on this calendar yet."
    assert Org.public_holidays(calendar.id) == []
  end

  test "a region holds what is local to it, and observes its country's holidays too", context do
    country = Fixtures.calendar(%{organisation_id: context.organisation.id})
    Fixtures.public_holiday(%{calendar_id: country.id, date: ~D[2026-10-26], name: "Labour Day"})

    {:ok, live, _html} = live(context.conn, ~p"/settings/calendars/#{country}")

    live |> form("#new-region", region: %{"name" => "Auckland"}) |> render_submit()

    assert [held, region] = Org.calendars(context.organisation.id)
    assert held.id == country.id
    assert region.name == "Auckland"
    assert region.country_code == country.country_code
    assert region.time_zone == country.time_zone

    {:ok, live, _html} = live(context.conn, ~p"/settings/calendars/#{region}")

    html =
      live
      |> form("#new-holiday", public_holiday: %{"date" => "2026-01-26", "name" => "Anniversary"})
      |> render_submit()

    assert html =~ "Anniversary"
    refute html =~ "Labour Day"

    observed = Org.observed_holidays(region.id, Date.range(~D[2026-01-01], ~D[2026-12-31]))

    assert Enum.map(observed, & &1.name) == ["Anniversary", "Labour Day"]

    {:ok, list, _html} = live(context.conn, ~p"/settings/calendars")
    row = list |> element("tr", "New Zealand — Auckland") |> render()

    assert row =~ ">2<"
  end

  test "a policy will not act on another policy's entitlement", context do
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})
    other = Fixtures.leave_policy(%{organisation_id: context.organisation.id, name: "Contractor"})
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})

    entitlement =
      Fixtures.policy_entitlement(%{leave_policy_id: other.id, leave_type_id: leave_type.id})

    {:ok, live, _html} = live(context.conn, ~p"/settings/policies/#{policy}")

    assert render_click(live, "remove", %{"id" => entitlement.id}) =~
             "That entitlement is not on this policy."

    assert [%{id: id}] = Policies.entitlements(other.id)
    assert id == entitlement.id
  end

  test "another policy's entitlement cannot be edited under this policy's name", context do
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})
    other = Fixtures.leave_policy(%{organisation_id: context.organisation.id, name: "Contractor"})
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})

    entitlement =
      Fixtures.policy_entitlement(%{leave_policy_id: other.id, leave_type_id: leave_type.id})

    assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
             live(context.conn, ~p"/settings/policies/#{policy}/entitlements/#{entitlement}")

    assert to == "/settings/policies/#{policy.id}"
    assert flash["error"] == "That entitlement is not on this policy."
  end

  test "a calendar will not let a holiday off another calendar", context do
    calendar = Fixtures.calendar(%{organisation_id: context.organisation.id})

    other =
      Fixtures.calendar(%{
        organisation_id: context.organisation.id,
        name: "Australia",
        country_code: "AU",
        time_zone: "Australia/Sydney"
      })

    holiday = Fixtures.public_holiday(%{calendar_id: other.id})

    {:ok, live, _html} = live(context.conn, ~p"/settings/calendars/#{calendar}")

    assert render_click(live, "remove", %{"id" => holiday.id}) =~
             "That holiday is not on this calendar."

    assert [^holiday] = Org.public_holidays(other.id)
  end

  test "the audit log says who changed what, and narrows to one person", context do
    {:ok, _leave_type} =
      Policies.create_leave_type(context.organisation, context.admin, %{
        name: "Study leave",
        unit: "days",
        position: 1
      })

    {:ok, live, html} = live(context.conn, ~p"/settings/audit")

    assert html =~ "leave type created"
    assert html =~ "Kit Rua"

    html = live |> form("#filter", filter: %{"person_id" => context.admin.id}) |> render_change()

    assert html =~ "Nothing has been recorded yet."
  end
end
