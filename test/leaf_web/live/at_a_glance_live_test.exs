defmodule LeafWeb.AtAGlanceLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Leave

  @taken Date.range(~D[2024-10-07], ~D[2024-10-11])
  @ahead ~D[2030-10-07]
  @refused ~D[2030-10-21]

  setup %{conn: conn} do
    workplace = Fixtures.workplace()

    Fixtures.balance_entry(%{
      person_id: workplace.person.id,
      leave_type_id: workplace.leave_type.id,
      amount: "100",
      expires_on: ~D[2030-12-31]
    })

    Map.put(workplace, :conn, sign_in(conn, workplace.person))
  end

  defp file(context, dates) do
    Fixtures.pending_request(context.person, %{
      leave_type_id: context.leave_type.id,
      dates: dates
    })
  end

  test "somebody the session does not name is sent to pick a name" do
    assert build_conn() |> get(~p"/") |> redirected_to() == "/sign-in"
  end

  test "a month that is not a month reads as this one", context do
    {:ok, _live, html} = live(context.conn, ~p"/?from[x]=1")

    assert html =~ "At a glance"
  end

  test "the balance says what is held and what becomes of it", context do
    {:ok, _taken} = context |> file(@taken) |> Leave.approve(context.manager)

    {:ok, _live, html} = live(context.conn, ~p"/")

    assert html =~ "Annual leave"
    assert html =~ "60 <small>hours</small>"
    assert html =~ "Expires 31 December"
  end

  test "a balance says what is waiting on an answer, and is not drawn down by it", context do
    file(context, [@ahead])

    {:ok, _live, html} = live(context.conn, ~p"/")

    assert html =~ "100 <small>hours</small>"
    assert html =~ "8 hours awaiting approval"
  end

  test "a leave type nothing is held in is left off the balances", context do
    empty =
      Fixtures.leave_type(%{
        organisation_id: context.person.organisation_id,
        name: "Sick leave",
        position: 2
      })

    Fixtures.balance_entry(%{person_id: context.person.id, leave_type_id: empty.id})

    {:ok, _live, html} = live(context.conn, ~p"/")

    assert html =~ "Annual leave"
    refute html =~ "Sick leave"
  end

  test "a request says when it is, what it comes to and where it got to", context do
    {:ok, _taken} = context |> file(@taken) |> Leave.approve(context.manager)
    file(context, [@ahead])

    {:ok, _refused} =
      context |> file([@refused]) |> Leave.decline(context.manager, "Three of you are away")

    {:ok, _live, html} = live(context.conn, ~p"/")

    assert html =~ "Mon 7 – Fri 11 Oct"
    assert html =~ "40 hours"
    assert html =~ "Taken"
    assert html =~ "Ines Vasquez · "

    assert html =~ "Mon 7 Oct"
    assert html =~ "8 hours"
    assert html =~ "Pending"
    assert html =~ "with Ines Vasquez since "

    assert html =~ "Declined"
    assert html =~ "Ines Vasquez said Three of you are away"
  end

  test "a request waiting on an answer is shown ahead of decided ones", context do
    for date <- [~D[2031-01-06], ~D[2031-02-03], ~D[2031-03-03], ~D[2031-04-07], ~D[2031-05-05]] do
      {:ok, _approved} = context |> file([date]) |> Leave.approve(context.manager)
    end

    file(context, [@ahead])

    {:ok, _live, html} = live(context.conn, ~p"/")

    assert html =~ "Mon 7 Oct"
    assert html =~ "Showing five."
    refute html =~ "Mon 6 Jan"
  end

  test "somebody with no work pattern yet still has a page, with no balances on it", context do
    fresh = Fixtures.person(%{organisation_id: context.person.organisation_id, name: "Kit Rua"})

    {:ok, _live, html} = live(sign_in(build_conn(), fresh), ~p"/")

    assert html =~ "At a glance"
    refute html =~ ~s(class="balance-sheet")
    refute html =~ "Annual leave"
  end

  test "somebody who has asked for nothing is told so", context do
    {:ok, _live, html} = live(context.conn, ~p"/")

    assert html =~ "You have not asked for any leave yet."
  end

  test "the calendar shows three months of the person's own days, and steps by three", context do
    file(context, [@ahead])

    {:ok, _live, html} = live(context.conn, ~p"/?from=2030-10")

    assert html =~ "<caption>October 2030</caption>"
    assert html =~ "<caption>November 2030</caption>"
    assert html =~ "<caption>December 2030</caption>"
    assert html =~ ~s(data-leave="pending")
    assert html =~ "/?from=2030-07"
    assert html =~ "/?from=2031-01"
  end
end
