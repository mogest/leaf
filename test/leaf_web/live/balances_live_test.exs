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
    {:ok, _live, html} = live(context.conn, ~p"/balances")

    assert html =~ "Annual leave"
    assert html =~ "100 hours"
    assert html =~ "lapses 31 December 2030"
    assert html =~ "Brought in"
  end

  test "a date that is not a date reads as today", context do
    {:ok, _live, html} = live(context.conn, ~p"/balances?as_at[x]=1")

    assert html =~ "Balances"
  end

  test "balances that are not there are not theirs to read", context do
    assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
             live(context.conn, ~p"/people/#{Ecto.UUID.generate()}/balances")

    assert flash["error"] == "Those balances are not yours to read."
  end

  test "a type that is offered but grants nothing is listed, and reads as empty", context do
    bereavement = recorded_only(context)

    {:ok, live, html} = live(context.conn, ~p"/balances")

    assert html =~ "Bereavement leave"
    assert html =~ "0 days"

    html = live |> element(~s(a[href^="/balances/#{bereavement.id}"])) |> render_click()

    assert html =~ "Nothing held."
    assert html =~ "Nothing has happened to it yet."
  end

  test "the date at the top is the whole page's question", context do
    {:ok, live, html} = live(context.conn, ~p"/balances")

    assert html =~ "100 hours"

    html = live |> form("#as-at") |> render_change(%{"ledger" => %{"as_at" => "2024-05-01"}})

    assert html =~ "as at 1 May 2024"
    assert html =~ "0 hours"
    assert html =~ "Nothing has happened to it yet."
  end

  test "a leave type that is nothing of theirs is no account of theirs", context do
    path = ~p"/balances/#{Ecto.UUID.generate()}"

    assert {:error, {:live_redirect, %{to: "/balances?as_at=" <> _date, flash: flash}}} =
             live(context.conn, path)

    assert flash["error"] == "There is no account to show for that."
  end

  test "somebody else's balances are not there to be read", context do
    other = Fixtures.person(%{organisation_id: context.organisation.id, name: "Kit Rua"})

    assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
             live(sign_in(build_conn(), other), ~p"/people/#{context.person}/balances")

    assert flash["error"] == "Those balances are not yours to read."
  end

  test "an administrator reads anybody's, from their record", context do
    admin =
      Fixtures.person(%{organisation_id: context.organisation.id, name: "Kit Rua", role: :admin})

    path = ~p"/people/#{context.person}/balances/#{context.leave_type}"
    {:ok, _live, html} = live(sign_in(build_conn(), admin), path)

    assert html =~ "Rae Halloran"
    assert html =~ "100 hours"
  end
end
