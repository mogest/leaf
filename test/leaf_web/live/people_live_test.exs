defmodule LeafWeb.PeopleLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Leave
  alias Leaf.People

  setup %{conn: conn} do
    organisation = Fixtures.organisation()

    admin =
      Fixtures.person(%{organisation_id: organisation.id, name: "Kit Rua", role: :admin})

    person = Fixtures.person(%{organisation_id: organisation.id, name: "Rae Halloran"})
    Fixtures.work_pattern(%{person_id: person.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})

    %{
      conn: sign_in(conn, admin),
      organisation: organisation,
      admin: admin,
      person: person,
      leave_type: leave_type
    }
  end

  test "the list says who works how much for whom", context do
    {:ok, _live, html} = live(context.conn, ~p"/people")

    assert html =~ "Rae Halloran"
    assert html =~ "40 (1 FTE)"
    assert html =~ "no work pattern"
  end

  test "a member is not the one to browse the organisation", context do
    other = Fixtures.person(%{organisation_id: context.organisation.id, name: "Ines Vasquez"})

    assert {:error, {:redirect, %{to: "/", flash: flash}}} =
             live(sign_in(context.conn, other), ~p"/people")

    assert flash["error"] == "That page is the administrator's."
  end

  test "somebody's record is not there for a colleague to read", context do
    other = Fixtures.person(%{organisation_id: context.organisation.id, name: "Ines Vasquez"})

    assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
             live(sign_in(context.conn, other), ~p"/people/#{context.person}")

    assert flash["error"] == "That record is not yours to read."
  end

  test "a member reading their own page cannot fire the removals it does not show them",
       context do
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})
    calendar = Fixtures.holiday_calendar(%{organisation_id: context.organisation.id})
    Fixtures.policy_assignment(%{person_id: context.person.id, leave_policy_id: policy.id})

    Fixtures.calendar_assignment(%{
      person_id: context.person.id,
      holiday_calendar_id: calendar.id
    })

    [pattern] = People.work_patterns(context.person)
    [assigned_policy] = People.policy_assignments(context.person)
    [assigned_calendar] = People.calendar_assignments(context.person)

    {:ok, live, html} = live(sign_in(context.conn, context.person), ~p"/people/#{context.person}")
    refute html =~ "Remove"

    assert render_click(live, "remove-work-pattern", %{"id" => pattern.id}) =~
             "That is not yours to do."

    assert render_click(live, "remove-policy-assignment", %{"id" => assigned_policy.id}) =~
             "That is not yours to do."

    assert render_click(live, "remove-calendar-assignment", %{"id" => assigned_calendar.id}) =~
             "That is not yours to do."

    assert People.work_patterns(context.person) == [pattern]
    assert [^assigned_policy] = People.policy_assignments(context.person)
    assert [^assigned_calendar] = People.calendar_assignments(context.person)
  end

  test "the form is not a member's to open, and the login identity is not its to set", context do
    assert {:error, {:redirect, %{to: "/", flash: flash}}} =
             live(sign_in(context.conn, context.person), ~p"/people/#{context.person}/edit")

    assert flash["error"] == "That page is the administrator's."

    {:ok, live, _html} = live(context.conn, ~p"/people/#{context.person}/edit")

    render_submit(live, "save", %{
      "person" => %{
        "name" => "Rae Halloran-Vale",
        "email" => "rae@example.test",
        "role" => "member",
        "employment_start_date" => "2024-03-04",
        "google_sub" => "108124"
      }
    })

    assert {:ok, amended} = People.fetch_person(context.person.id)
    assert amended.name == "Rae Halloran-Vale"
    assert is_nil(amended.google_sub)
  end

  test "adding somebody puts them on record and opens their page", context do
    {:ok, live, _html} = live(context.conn, ~p"/people/new")

    live
    |> form("#person",
      person: %{
        "name" => "Tomas Vale",
        "email" => "tomas@example.test",
        "role" => "member",
        "employment_start_date" => "2026-01-05",
        "manager_id" => context.admin.id
      }
    )
    |> render_submit()

    assert [_kit, _rae, tomas] = People.people(context.organisation.id) |> Enum.sort_by(& &1.name)
    assert tomas.name == "Tomas Vale"
    assert tomas.manager_id == context.admin.id
  end

  test "a person's page shows their record and what it means for their balances", context do
    {:ok, _live, html} = live(context.conn, ~p"/people/#{context.person}")

    assert html =~ "Rae Halloran"
    assert html =~ "from 4 March 2024"
    assert html =~ "nobody, so an administrator decides"
    assert html =~ "Mon–Fri 8"
    assert html =~ "40 h/wk, 1 FTE"
    assert html =~ "On no policy, so nothing is granted."
  end

  test "a week worked unevenly is said run by run, the days off left out", context do
    other = Fixtures.person(%{organisation_id: context.organisation.id, name: "Ines Vasquez"})

    Fixtures.work_pattern(%{
      person_id: other.id,
      tuesday_hours: "6",
      wednesday_hours: "0",
      saturday_hours: "4"
    })

    {:ok, _live, html} = live(context.conn, ~p"/people/#{other}")

    assert html =~ "Mon 8, Tue 6, Thu–Fri 8, Sat 4"
  end

  test "a work pattern can be added, amended and removed", context do
    {:ok, live, _html} = live(context.conn, ~p"/people/#{context.person}/work-patterns/new")

    live
    |> form("#work-pattern",
      work_pattern: %{
        "effective_from" => "2026-01-01",
        "monday_hours" => "9",
        "tuesday_hours" => "9",
        "wednesday_hours" => "9",
        "thursday_hours" => "0",
        "friday_hours" => "9",
        "saturday_hours" => "0",
        "sunday_hours" => "0"
      }
    )
    |> render_submit()

    assert [_first, added] = People.work_patterns(context.person)
    assert added.effective_from == ~D[2026-01-01]

    {:ok, live, _html} =
      live(context.conn, ~p"/people/#{context.person}/work-patterns/#{added}")

    live
    |> form("#work-pattern", work_pattern: %{"effective_from" => "2026-02-01"})
    |> render_submit()

    assert [_first, %{effective_from: ~D[2026-02-01]}] = People.work_patterns(context.person)

    {:ok, live, _html} = live(context.conn, ~p"/people/#{context.person}")
    live |> element("button[phx-value-id='#{added.id}']") |> render_click()

    assert [_only] = People.work_patterns(context.person)
  end

  test "one person's page will not act on somebody else's records", context do
    other = Fixtures.person(%{organisation_id: context.organisation.id, name: "Ines Vasquez"})
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})
    calendar = Fixtures.holiday_calendar(%{organisation_id: context.organisation.id})
    pattern = Fixtures.work_pattern(%{person_id: other.id})

    assigned_policy =
      Fixtures.policy_assignment(%{person_id: other.id, leave_policy_id: policy.id})

    assigned_calendar =
      Fixtures.calendar_assignment(%{person_id: other.id, holiday_calendar_id: calendar.id})

    {:ok, live, _html} = live(context.conn, ~p"/people/#{context.person}")

    assert render_click(live, "remove-work-pattern", %{"id" => pattern.id}) =~
             "That is not on their record."

    assert render_click(live, "remove-policy-assignment", %{"id" => assigned_policy.id}) =~
             "That is not on their record."

    assert render_click(live, "remove-calendar-assignment", %{"id" => assigned_calendar.id}) =~
             "That is not on their record."

    assert Enum.map(People.work_patterns(other), & &1.id) == [pattern.id]
    assert Enum.map(People.policy_assignments(other), & &1.id) == [assigned_policy.id]
    assert Enum.map(People.calendar_assignments(other), & &1.id) == [assigned_calendar.id]
  end

  test "somebody else's work pattern cannot be edited under this person's name", context do
    other = Fixtures.person(%{organisation_id: context.organisation.id, name: "Ines Vasquez"})
    pattern = Fixtures.work_pattern(%{person_id: other.id})

    assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
             live(context.conn, ~p"/people/#{context.person}/work-patterns/#{pattern}")

    assert to == "/people/#{context.person.id}"
    assert flash["error"] == "That work pattern is not theirs."
  end

  test "a balance can be entered by hand", context do
    {:ok, live, _html} = live(context.conn, ~p"/people/#{context.person}/balance-entries/new")

    live
    |> form("#balance-entry",
      balance_entry: %{
        "kind" => "adjustment",
        "leave_type_id" => context.leave_type.id,
        "date" => "2026-01-05",
        "amount" => "12.5",
        "reason" => "Carried over by hand"
      }
    )
    |> render_submit()

    assert [entry] = Leave.balance_entries(context.person, ~D[2026-12-31])
    assert entry.kind == :adjustment
    assert Decimal.equal?(entry.amount, "12.5")
  end

  test "an adjustment without a reason is refused", context do
    {:ok, live, _html} = live(context.conn, ~p"/people/#{context.person}/balance-entries/new")

    html =
      live
      |> form("#balance-entry",
        balance_entry: %{
          "kind" => "adjustment",
          "leave_type_id" => context.leave_type.id,
          "date" => "2026-01-05",
          "amount" => "12.5",
          "reason" => ""
        }
      )
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert Leave.balance_entries(context.person, ~D[2026-12-31]) == []
  end
end
