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

  test "a leave type can be added, amended and withdrawn", context do
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

    {:ok, live, html} = live(context.conn, ~p"/settings/leave-types")
    assert html =~ "Study"

    html = live |> element("button", "Withdraw") |> render_click()
    assert html =~ "withdrawn"

    {:ok, withdrawn} = Policies.fetch_leave_type(leave_type.id)
    assert withdrawn.archived_at
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

    assert html =~ "160 each year, reckoned from their start date, accruing day by day"
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
    |> form("#new-calendar", holiday_calendar: %{"name" => "New Zealand", "country_code" => "NZ"})
    |> render_submit()

    assert [calendar] = Org.holiday_calendars(context.organisation.id)

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
