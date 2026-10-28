defmodule LeafWeb.SettingsLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Audit.Entry
  alias Leaf.Fixtures
  alias Leaf.Org
  alias Leaf.Policies
  alias Leaf.Repo

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
    {:ok, live, _html} = live(context.conn, ~p"/settings/leave-types/new")
    assert has_element?(live, ~s(#leave_type_position[value="1"]))

    assert live |> form("#leave-type", leave_type: %{"name" => ""}) |> render_submit() =~
             "can&#39;t be blank"

    live
    |> form("#leave-type",
      leave_type: %{"name" => "Study leave", "unit" => "days", "position" => "1"}
    )
    |> render_submit()

    assert [leave_type] = Policies.leave_types(context.organisation.id)
    assert leave_type.name == "Study leave"

    {:ok, live, _html} = live(context.conn, ~p"/settings/leave-types/#{leave_type}")

    live
    |> form("#leave-type", leave_type: %{"name" => "Study", "suspends_accrual" => "true"})
    |> render_submit()

    {:ok, live, html} = live(context.conn, ~p"/settings/leave-types")
    assert html =~ "Study"

    assert live |> element("button", "Withdraw") |> render_click() =~ "Study withdrawn."

    {:ok, archived} = Policies.fetch_leave_type(leave_type.id)
    assert archived.archived_at
    assert archived.suspends_accrual

    {:ok, _page, html} = live(context.conn, ~p"/settings/leave-types/#{leave_type}")
    assert html =~ "It can&#39;t be added to new policies"

    assert live |> element("button", "Restore") |> render_click() =~ "Study restored."
    assert {:ok, %{archived_at: nil}} = Policies.fetch_leave_type(leave_type.id)
  end

  test "a policy grants what its entitlements say, in words", context do
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})
    {:ok, live, _html} = live(context.conn, ~p"/settings/policies/new")

    assert live |> form("#policy", leave_policy: %{"name" => ""}) |> render_submit() =~
             "can&#39;t be blank"

    live |> form("#policy", leave_policy: %{"name" => "NZ employee"}) |> render_submit()

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
        "qualifying_months" => "6",
        "takeable_after_months" => "3",
        "grant_timing" => "daily",
        "pro_rated_by_fte" => "true",
        "expiry_rule" => "never"
      }
    )
    |> render_submit()

    {:ok, _live, html} = live(context.conn, ~p"/settings/policies")
    assert html =~ "one leave type"

    jury = Fixtures.leave_type(%{organisation_id: context.organisation.id, name: "Jury service"})

    recorded =
      Fixtures.policy_entitlement(%{
        leave_policy_id: policy.id,
        leave_type_id: jury.id,
        effective_from: ~D[2099-01-01],
        amount_source: :none
      })

    {:ok, live, html} = live(context.conn, ~p"/settings/policies/#{policy}")

    assert html =~ "160 hours a year <small>pro-rated</small>"
    assert html =~ "Start date <small>first granted after 6 months</small>"
    assert html =~ "taken after 3 months"
    assert html =~ "Day by day"
    assert html =~ "Rolls over"
    assert html =~ "from 1 January 2099"
    assert html =~ "Recorded only"

    live |> element("#entitlement-#{recorded.id} button", "Remove") |> render_click()
    html = live |> element("button", "Remove") |> render_click()
    assert html =~ "This policy grants nothing yet."
  end

  test "a policy is withdrawn from the list, and it and a calendar are edited on their own pages",
       context do
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})
    {:ok, live, _html} = live(context.conn, ~p"/settings/policies")

    live |> element("button", "Withdraw") |> render_click()
    assert {:ok, %{archived_at: %DateTime{}}} = Policies.fetch_leave_policy(policy.id)

    {:ok, _page, html} = live(context.conn, ~p"/settings/policies/#{policy}")
    assert html =~ "It can&#39;t be assigned to anyone new"

    live |> element("button", "Restore") |> render_click()
    assert {:ok, %{archived_at: nil}} = Policies.fetch_leave_policy(policy.id)

    {:ok, live, _html} = live(context.conn, ~p"/settings/policies/#{policy}/edit")

    {:ok, live, _html} =
      live
      |> form("#policy", leave_policy: %{"name" => "Contractor"})
      |> render_submit()
      |> follow_redirect(context.conn)

    assert page_title(live) =~ "Contractor"

    calendar = Fixtures.calendar(%{organisation_id: context.organisation.id})
    {:ok, live, _html} = live(context.conn, ~p"/settings/calendars/#{calendar}/edit")

    {:ok, live, _html} =
      live
      |> form("#calendar", calendar: %{"name" => "Aotearoa"})
      |> render_submit()
      |> follow_redirect(context.conn)

    assert page_title(live) =~ "Aotearoa"
  end

  test "an entitlement that grants nothing asks nothing about granting", context do
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})

    {:ok, live, html} = live(context.conn, ~p"/settings/policies/#{policy}/entitlements/new")
    assert html =~ "Grant period"

    html =
      live
      |> form("#entitlement",
        policy_entitlement: %{"leave_type_id" => leave_type.id, "amount_source" => "none"}
      )
      |> render_change()

    refute html =~ "Grant period"
    refute html =~ "What happens to unused leave"

    live |> form("#entitlement") |> render_submit()

    assert [%{amount_source: :none, grant_period: nil, expiry_rule: :never}] =
             Policies.entitlements(policy.id)
  end

  test "an allowance moved off the start date shows the timing it is held to", context do
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})

    entitlement =
      Fixtures.policy_entitlement(%{
        leave_policy_id: policy.id,
        leave_type_id: leave_type.id,
        amount_source: :public_holidays,
        grant_amount: nil
      })

    {:ok, live, _html} =
      live(context.conn, ~p"/settings/policies/#{policy}/entitlements/#{entitlement}")

    live
    |> form("#entitlement", policy_entitlement: %{"grant_timing" => "period_start"})
    |> render_change()

    live
    |> form("#entitlement", policy_entitlement: %{"grant_basis" => "calendar_year"})
    |> render_change()

    assert has_element?(
             live,
             ~s(input[name="policy_entitlement[grant_timing]"][checked][value="daily"])
           )
  end

  test "a new entitlement offers only what its choices leave meaning, and restores what it hid",
       context do
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})
    period = ~s(select[name="policy_entitlement[grant_period]"] option)
    period_start = ~s(input[name="policy_entitlement[grant_timing]"][value="period_start"])
    monthly = ~s(input[name="policy_entitlement[grant_timing]"][value="monthly"])

    {:ok, live, _html} = live(context.conn, ~p"/settings/policies/#{policy}/entitlements/new")
    assert has_element?(live, monthly)

    live
    |> form("#entitlement", policy_entitlement: %{"grant_period" => "quarter"})
    |> render_change()

    refute has_element?(live, monthly)

    live
    |> form("#entitlement", policy_entitlement: %{"grant_basis" => "birthday"})
    |> render_change()

    assert has_element?(live, period, "Year")
    refute has_element?(live, period, "Month")

    holidays = %{"amount_source" => "public_holidays", "grant_basis" => "employment_date"}
    live |> form("#entitlement", policy_entitlement: holidays) |> render_change()
    assert has_element?(live, period_start)

    holidays = %{holidays | "grant_basis" => "calendar_year"}
    live |> form("#entitlement", policy_entitlement: holidays) |> render_change()
    refute has_element?(live, period_start)

    chosen = %{"leave_type_id" => leave_type.id, "amount_source" => "none"}
    live |> form("#entitlement", policy_entitlement: chosen) |> render_change()

    live
    |> form("#entitlement", policy_entitlement: %{"amount_source" => "fixed"})
    |> render_change()

    live
    |> form("#entitlement", policy_entitlement: %{"grant_amount" => "160"})
    |> render_submit()

    assert [
             %{
               amount_source: :fixed,
               grant_period: :year,
               grant_basis: :employment_date,
               grant_timing: :daily,
               pro_rated_by_fte: true,
               expiry_rule: :never
             }
           ] = Policies.entitlements(policy.id)
  end

  test "a calendar holds the holidays put on it, and lets one off again", context do
    {:ok, live, _html} = live(context.conn, ~p"/settings/calendars/new")

    assert live |> form("#calendar", calendar: %{"name" => ""}) |> render_submit() =~
             "can&#39;t be blank"

    live
    |> form("#calendar",
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

    {:ok, live, _html} = live(context.conn, ~p"/settings/calendars/#{country}/regions/new")

    assert live |> form("#region", calendar: %{"name" => ""}) |> render_submit() =~
             "can&#39;t be blank"

    {:ok, live, html} =
      live
      |> form("#region", calendar: %{"name" => "Auckland"})
      |> render_submit()
      |> follow_redirect(context.conn)

    assert html =~ "Region Auckland added to New Zealand."

    assert [held, region] = Org.calendars(context.organisation.id)
    assert held.id == country.id
    assert region.name == "Auckland"
    assert region.country_code == nil
    assert region.time_zone == country.time_zone

    assert {:ok, %{country_code: nil}} =
             Org.update_calendar(region, nil, %{"country_code" => "AU"})

    assert {:error, {:live_redirect, %{to: "/settings/calendars", flash: flash}}} =
             live(context.conn, ~p"/settings/calendars/#{region}/regions/new")

    assert flash["error"] == "Regions can only be added to a country."

    html =
      live
      |> form("#new-holiday", public_holiday: %{"date" => "2026-01-26", "name" => "Anniversary"})
      |> render_submit()

    assert html =~ "Anniversary"
    refute html =~ "Labour Day"

    observed = Org.observed_holidays(region, Date.range(~D[2026-01-01], ~D[2026-12-31]))

    assert Enum.map(observed, & &1.name) == ["Anniversary", "Labour Day"]
  end

  test "an entitlement shows how it plays out for sample people as it is edited", context do
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})

    entitlement =
      Fixtures.policy_entitlement(%{
        leave_policy_id: policy.id,
        leave_type_id: leave_type.id,
        grant_amount: "365"
      })

    {:ok, live, _html} =
      live(context.conn, ~p"/settings/policies/#{policy}/entitlements/#{entitlement}")

    html = render_async(live, 2000)
    assert html =~ "<h2>Preview</h2>"
    assert html =~ "Granted in the first year"
    refute html =~ "above the cap"

    live |> form("#entitlement", policy_entitlement: %{"expiry_rule" => "cap"}) |> render_change()
    live |> form("#entitlement", policy_entitlement: %{"rollover_cap" => "40"}) |> render_change()

    render_async(live, 2000)

    assert has_element?(
             live,
             ~s(circle[aria-label="Loses 325 hours above the cap on 3 March 2025"])
           )

    # A year's 365 trimmed to 40, then 40 and the next year's 365 trimmed to 40, twice.
    assert live |> element("dl") |> render() ==
             "<dl><div><dt>Granted in the first year</dt><dd>365 hours</dd></div>" <>
               "<div><dt>Highest balance</dt><dd>405 hours</dd></div>" <>
               "<div><dt>Lost over three years</dt><dd>1055 hours</dd></div></dl>"

    assert live |> element("button", "Three days a week") |> render_click() =~
             "Loses 179 hours above the cap on 3 March 2025"

    live |> form("#entitlement", policy_entitlement: %{"grant_amount" => "-1"}) |> render_change()

    html = render_async(live, 2000)
    assert html =~ "Fix the errors to see the preview."
    assert html =~ "Loses 179 hours above the cap on 3 March 2025"
  end

  test "a new entitlement shows nothing playing out once its leave type is cleared", context do
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})

    {:ok, live, html} = live(context.conn, ~p"/settings/policies/#{policy}/entitlements/new")
    refute html =~ "<h2>Preview</h2>"

    live
    |> form("#entitlement",
      policy_entitlement: %{"leave_type_id" => leave_type.id, "grant_amount" => "160"}
    )
    |> render_change()

    live |> form("#entitlement", policy_entitlement: %{"leave_type_id" => ""}) |> render_change()

    refute render_async(live, 2000) =~ "<h2>Preview</h2>"
  end

  test "a policy will not act on another policy's entitlement", context do
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})
    other = Fixtures.leave_policy(%{organisation_id: context.organisation.id, name: "Contractor"})
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})

    entitlement =
      Fixtures.policy_entitlement(%{leave_policy_id: other.id, leave_type_id: leave_type.id})

    {:ok, live, _html} = live(context.conn, ~p"/settings/policies/#{policy}")

    assert render_click(live, "remove", %{"id" => entitlement.id}) =~
             "Entitlement not found."

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
    assert flash["error"] == "Entitlement not found."
  end

  test "an entitlement leave has been taken against closes, and says why nothing else changes",
       context do
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})
    person = Fixtures.person(%{organisation_id: context.organisation.id})

    entitlement =
      Fixtures.policy_entitlement(%{leave_policy_id: policy.id, leave_type_id: leave_type.id})

    Fixtures.policy_assignment(%{person_id: person.id, leave_policy_id: policy.id})

    Fixtures.leave_request(%{
      person_id: person.id,
      days: [%{leave_type_id: leave_type.id, date: ~D[2026-08-20], amount: "4", unit: :hours}]
    })

    {:ok, live, _html} =
      live(context.conn, ~p"/settings/policies/#{policy}/entitlements/#{entitlement}")

    assert render_async(live, 2000) =~ "so changes to its terms can&#39;t be saved"

    assert live
           |> form("#entitlement", policy_entitlement: %{"grant_amount" => "200"})
           |> render_submit() =~ "Leave has already been taken under this entitlement"

    {:ok, live, _html} =
      live(context.conn, ~p"/settings/policies/#{policy}/entitlements/#{entitlement}")

    live
    |> form("#entitlement", policy_entitlement: %{"effective_to" => "2027-03-31"})
    |> render_submit()

    assert_redirect(live, ~p"/settings/policies/#{policy}")
    assert [%{effective_to: ~D[2027-03-31]}] = Policies.entitlements(policy.id)
  end

  test "closing an entitlement under booked leave warns, and saves once told to", context do
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})
    leave_type = Fixtures.leave_type(%{organisation_id: context.organisation.id})
    person = Fixtures.person(%{organisation_id: context.organisation.id, name: "Ari Moana"})
    Fixtures.work_pattern(%{person_id: person.id})
    Fixtures.policy_assignment(%{person_id: person.id, leave_policy_id: policy.id})

    entitlement =
      Fixtures.policy_entitlement(%{leave_policy_id: policy.id, leave_type_id: leave_type.id})

    Fixtures.leave_request(%{
      person_id: person.id,
      days: [%{leave_type_id: leave_type.id, date: ~D[2024-11-04], amount: "8", unit: :hours}]
    })

    {:ok, live, _html} =
      live(context.conn, ~p"/settings/policies/#{policy}/entitlements/#{entitlement}")

    closed = %{"granted_to" => "2024-09-30", "effective_to" => "2024-09-30"}
    warned = live |> form("#entitlement", policy_entitlement: closed) |> render_submit()

    assert warned =~ "Ari Moana: 4 November 2024"
    assert [%{effective_to: nil}] = Policies.entitlements(policy.id)

    live
    |> form("#entitlement", policy_entitlement: closed)
    |> put_submitter("button[name=confirmed]")
    |> render_submit()

    assert_redirect(live, ~p"/settings/policies/#{policy}")
    assert [%{effective_to: ~D[2024-09-30]}] = Policies.entitlements(policy.id)
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
             "Holiday not found."

    assert [^holiday] = Org.public_holidays(other.id)
  end

  test "the audit log says who changed what, and narrows to one person and a day", context do
    {:ok, _leave_type} =
      Policies.create_leave_type(context.organisation, context.admin, %{
        name: "Study leave",
        unit: "days",
        position: 1
      })

    {:ok, live, html} = live(context.conn, ~p"/settings/audit")

    assert html =~ "leave type created"
    assert html =~ "Kit Rua"

    live |> form("#filter", filter: %{"about" => context.admin.id}) |> render_change()
    assert_patch(live, ~p"/settings/audit?#{%{about: context.admin.id}}")
    assert render(live) =~ "Nothing has been recorded."

    live
    |> form("#filter", filter: %{"about" => "", "through" => "2000-01-01"})
    |> render_change()

    assert_patch(live, ~p"/settings/audit?through=2000-01-01")

    assert render(live) =~ "Nothing has been recorded."

    {:ok, _live, html} = live(context.conn, ~p"/settings/audit?about=banana&through=soon&page=-1")
    assert html =~ "leave type created"

    {:ok, _live, html} = live(context.conn, ~p"/settings/audit?about=#{Ecto.UUID.generate()}")
    assert html =~ "leave type created"
  end

  test "the audit log pages through its entries a hundred at a time", context do
    Repo.insert_all(
      Entry,
      for _ <- 1..101 do
        %{
          id: Ecto.UUID.generate(),
          action: "person.updated",
          entity_type: "people",
          entity_id: context.admin.id,
          subject_person_id: context.admin.id,
          changes: %{},
          inserted_at: DateTime.utc_now()
        }
      end
    )

    {:ok, live, _html} = live(context.conn, ~p"/settings/audit")
    assert has_element?(live, "form nav", "Page 1 of 2")
    refute has_element?(live, "nav a[href]", "Newer")
    assert has_element?(live, ~s(nav a[href="/settings/audit?page=2"]), "Older")

    {:ok, live, _html} =
      live(
        context.conn,
        ~p"/settings/audit?about=#{context.admin.id}&through=2099-12-31&page=9&x=1"
      )

    assert has_element?(live, "main > nav", "Page 2 of 2")
    assert has_element?(live, "tbody tr")
    refute has_element?(live, "tbody tr + tr")

    newer = ~p"/settings/audit?#{[about: context.admin.id, page: 1, through: "2099-12-31"]}"
    assert has_element?(live, ~s(nav a[href="#{newer}"]), "Newer")
  end
end
