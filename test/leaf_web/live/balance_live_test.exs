defmodule LeafWeb.BalanceLiveTest do
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
      date: ~D[2024-01-01],
      expires_on: ~D[2030-12-31]
    })

    %{
      conn: conn,
      organisation: organisation,
      person: person,
      leave_type: leave_type
    }
  end

  defp ledger(context, person) do
    ~p"/people/#{person}/balances/#{context.leave_type}"
  end

  test "the account says what is held, in what lots, and every movement", context do
    conn = sign_in(context.conn, context.person)

    {:ok, _live, html} = live(conn, ledger(context, context.person))

    assert html =~ "Annual leave"
    assert html =~ "100 hours"
    assert html =~ "lapses 31 December 2030"
    assert html =~ "Brought in"
    assert html =~ "one movement"
  end

  test "a date before there was an account to hold sends them back", context do
    conn = sign_in(context.conn, context.person)

    assert {:error, {:live_redirect, %{flash: flash}}} =
             live(conn, ledger(context, context.person) <> "?as_at=2023-06-01")

    assert flash["error"] == "There is no account to show for that."
  end

  test "somebody else's account is not there to be read", context do
    other = Fixtures.person(%{organisation_id: context.organisation.id, name: "Kit Rua"})

    assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
             live(sign_in(context.conn, other), ledger(context, context.person))

    assert flash["error"] == "That account is not yours to read."
  end

  test "an administrator may read anybody's", context do
    admin =
      Fixtures.person(%{organisation_id: context.organisation.id, name: "Kit Rua", role: :admin})

    {:ok, _live, html} = live(sign_in(context.conn, admin), ledger(context, context.person))

    assert html =~ "Rae Halloran"
  end
end
