defmodule LeafWeb.BalancesLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures

  setup %{conn: conn} do
    organisation = Fixtures.organisation()
    person = Fixtures.person(%{organisation_id: organisation.id, name: "Rae Halloran"})
    Fixtures.work_pattern(%{person_id: person.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})

    Fixtures.balance_entry(%{
      person_id: person.id,
      leave_type_id: leave_type.id,
      amount: "100",
      date: ~D[2024-06-01],
      expires_on: ~D[2030-12-31]
    })

    %{
      conn: sign_in(conn, person),
      organisation: organisation,
      person: person,
      leave_type: leave_type
    }
  end

  # A type the policy offers and grants nothing for holds no account until there is leave against
  # it, which is the whole reason the page lists what is offered as well as what is held.
  defp recorded_only(context) do
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})

    bereavement =
      Fixtures.leave_type(%{
        organisation_id: context.organisation.id,
        name: "Bereavement leave",
        unit: :days,
        position: 2
      })

    Fixtures.policy_entitlement(%{
      leave_policy_id: policy.id,
      leave_type_id: bereavement.id,
      amount_source: :none,
      grant_amount: nil,
      grant_basis: nil,
      grant_period: nil,
      grant_timing: nil
    })

    Fixtures.policy_assignment(%{person_id: context.person.id, leave_policy_id: policy.id})

    bereavement
  end

  test "the page reads the first account, saying what is held and how it got there", context do
    {:ok, live, html} = live(context.conn, ~p"/balances?as_at=2024-06-30")

    assert html =~ "<h1>Your balances</h1>"
    assert has_element?(live, ~s(#pages a[aria-current]), "Your balances")
    assert html =~ "Annual leave"
    assert html =~ "100 hours"
    assert html =~ "expiring 31 December 2030"
    assert html =~ "1 April 2024 – 31 March 2025"
    assert has_element?(live, "tbody tr + tr", ~r/1 June\s*Opening balance/)

    assert has_element?(
             live,
             ~s(a[aria-label="Earlier year"][href$="as_at=2024-06-30&year=2023"])
           )

    refute has_element?(live, ~s(a[aria-label="Later year"]))
    assert has_element?(live, "header a.step[href] + a.step:not([href])")

    {:ok, live, _html} = live(context.conn, ~p"/balances?as_at=2024-06-30&year=2023")

    assert has_element?(live, "tbody tr + tr", ~r/4 March\s*Started/)
  end

  test "an accruing balance reads as earned a month at a time, booked leave and all", context do
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})

    Fixtures.policy_entitlement(%{
      leave_policy_id: policy.id,
      leave_type_id: context.leave_type.id
    })

    Fixtures.policy_assignment(%{person_id: context.person.id, leave_policy_id: policy.id})

    Fixtures.leave_request(%{
      person_id: context.person.id,
      days: [
        %{leave_type_id: context.leave_type.id, date: ~D[2025-02-03], amount: "8", unit: :hours}
      ]
    })

    {:ok, live, _html} = live(context.conn, ~p"/balances?as_at=2025-01-01")

    assert has_element?(live, "thead th", "Earned")
    assert has_element?(live, "tbody tr + tr td", "Earned")
    assert has_element?(live, ~s(figure polyline[data-tone="spent"]))
    assert has_element?(live, "figure li", "As at 1 January")
  end

  test "leave taken after the date read at reads as booked, and is out of the balance after it",
       context do
    for date <- [~D[2024-07-01], ~D[2024-09-02]] do
      Fixtures.leave_request(%{
        person_id: context.person.id,
        days: [%{leave_type_id: context.leave_type.id, date: date, amount: "8", unit: :hours}]
      })
    end

    {:ok, live, html} = live(context.conn, ~p"/balances?as_at=2024-08-01")

    assert has_element?(live, "tbody tr + tr", ~r/1 July\s*Taken, 1 day/)
    assert has_element?(live, "tbody tr + tr", ~r/2 September\s*Booked, 1 day/)
    assert has_element?(live, "tbody th small", "booked")
    assert html =~ ~r/without booked leave.*92 hours.*with booked leave.*84 hours/s

    {:ok, _live, html} = live(context.conn, ~p"/balances?as_at=2024-09-30")

    assert html =~ "<dt>Balance</dt>"
  end

  test "a date that is not a date reads as today", context do
    {:ok, _live, html} = live(context.conn, ~p"/balances?as_at[x]=1")

    assert html =~ "Your balances"
  end

  test "balances that are not there are not theirs to read", context do
    assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
             live(context.conn, ~p"/people/#{Ecto.UUID.generate()}/balances")

    assert flash["error"] == "You don't have access to those balances."
  end

  test "a type that is offered but grants nothing is listed bare, and says it is recorded only",
       context do
    bereavement = recorded_only(context)
    link = ~s(a[href^="/balances/#{bereavement.id}"])

    {:ok, live, _html} = live(context.conn, ~p"/balances")

    assert has_element?(live, link, "Bereavement leave")
    refute has_element?(live, link <> " > span + span")

    html = live |> element(link) |> render_click()

    assert html =~ "This leave doesn&#39;t build up. It&#39;s only recorded when taken."
    refute html =~ "<dt>Balance"
    refute html =~ "Expiry"
    refute has_element?(live, "table")

    Fixtures.leave_request(%{
      person_id: context.person.id,
      days: [%{leave_type_id: bereavement.id, date: ~D[2024-07-01], amount: "0.5", unit: :days}]
    })

    Fixtures.leave_request(%{
      person_id: context.person.id,
      status: :pending,
      days: [%{leave_type_id: bereavement.id, date: ~D[2024-07-02], amount: "1", unit: :days}]
    })

    {:ok, _live, html} = live(context.conn, ~p"/balances/#{bereavement}")

    assert html =~ "This leave doesn&#39;t build up. It&#39;s only recorded when taken."
    assert html =~ "1 day awaiting approval, not yet deducted"

    {:ok, live, html} = live(context.conn, ~p"/balances/#{bereavement}?as_at=2024-07-31")

    # Leave counted in days says how many in its figure, so the line does not count them again.
    assert has_element?(live, "tbody tr + tr", ~r/^\s*1 July\s*Taken\s*-0.5\s*$/)
    refute has_element?(live, "figure")
    refute html =~ "Carried forward"

    {:ok, _live, html} = live(context.conn, ~p"/balances/#{bereavement}?as_at=2023-06-01")

    assert html =~ "This leave doesn&#39;t build up. It&#39;s only recorded when taken."
  end

  test "a type granted by policy reads as a figure before tracking started, leave or none",
       context do
    from = ~D[2023-06-01]

    person =
      Fixtures.person(%{
        organisation_id: context.organisation.id,
        name: "Kit Rua",
        employment_start_date: from
      })

    Fixtures.work_pattern(%{person_id: person.id, effective_from: from})
    policy = Fixtures.leave_policy(%{organisation_id: context.organisation.id})

    Fixtures.policy_entitlement(%{
      leave_policy_id: policy.id,
      leave_type_id: context.leave_type.id,
      effective_from: from
    })

    Fixtures.policy_assignment(%{
      person_id: person.id,
      leave_policy_id: policy.id,
      effective_from: from
    })

    conn = sign_in(build_conn(), person)
    {:ok, _live, html} = live(conn, ~p"/balances?as_at=2023-12-01")

    assert html =~ "Annual leave"
    assert html =~ "<dd>0 hours</dd>"
    refute html =~ "nothing accrues"

    Fixtures.leave_request(%{
      person_id: person.id,
      days: [
        %{leave_type_id: context.leave_type.id, date: ~D[2023-11-01], amount: "8", unit: :hours}
      ]
    })

    {:ok, _live, html} = live(conn, ~p"/balances?as_at=2023-12-01")

    assert html =~ "<dd>-8 hours</dd>"
    refute html =~ "nothing accrues"
  end

  test "leave left with no work pattern behind it reads as not set up rather than failing",
       context do
    # Asked for on a pattern reaching back before tracking started, which has since been removed.
    Fixtures.leave_request(%{
      person_id: context.person.id,
      status: :pending,
      days: [
        %{leave_type_id: context.leave_type.id, date: ~D[2023-11-01], amount: "8", unit: :hours}
      ]
    })

    {:ok, _live, html} = live(context.conn, ~p"/balances")

    assert html =~
             "Balances can&#39;t be calculated until you have a work pattern and a calendar for every day of employment."
  end

  test "the date at the top is the whole page's question", context do
    {:ok, live, html} = live(context.conn, ~p"/balances")

    assert html =~ "100 hours"

    html = live |> form("#as-at") |> render_change(%{"ledger" => %{"as_at" => "2024-05-01"}})

    assert html =~ "as at 1 May 2024"
    assert html =~ "0 hours"
    refute has_element?(live, "table")
  end

  test "a leave type that is nothing of theirs is no account of theirs", context do
    path = ~p"/balances/#{Ecto.UUID.generate()}"

    assert {:error, {:live_redirect, %{to: "/balances?as_at=" <> _date, flash: flash}}} =
             live(context.conn, path)

    assert flash["error"] == "No balance found for that leave type."
  end

  test "somebody else's balances are not there to be read", context do
    other = Fixtures.person(%{organisation_id: context.organisation.id, name: "Kit Rua"})

    assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
             live(sign_in(build_conn(), other), ~p"/people/#{context.person}/balances")

    assert flash["error"] == "You don't have access to those balances."
  end

  test "an administrator reads anybody's, from their record", context do
    admin =
      Fixtures.person(%{organisation_id: context.organisation.id, name: "Kit Rua", role: :admin})

    path = ~p"/people/#{context.person}/balances/#{context.leave_type}"
    {:ok, live, html} = live(sign_in(build_conn(), admin), path)

    assert html =~ "<h1>Balances</h1>"
    assert has_element?(live, ~s(#pages a[aria-current]), "People")
    refute has_element?(live, ~s(#pages a[aria-current]), "Your balances")
    assert html =~ "Rae Halloran"
    assert html =~ "100 hours"
  end

  test "somebody who has left reads as having left, after all that happened to them", context do
    admin =
      Fixtures.person(%{organisation_id: context.organisation.id, name: "Kit Rua", role: :admin})

    left =
      Fixtures.person(%{
        organisation_id: context.organisation.id,
        name: "Ari Moana",
        employment_end_date: ~D[2025-06-30]
      })

    Fixtures.work_pattern(%{person_id: left.id})

    Fixtures.balance_entry(%{
      person_id: left.id,
      leave_type_id: context.leave_type.id,
      amount: "8",
      date: ~D[2024-06-01]
    })

    path = ~p"/people/#{left}/balances?as_at=2025-07-15"
    {:ok, live, _html} = live(sign_in(build_conn(), admin), path)

    assert has_element?(live, "tbody tr + tr", ~r/30 June\s*Left/)
  end
end
