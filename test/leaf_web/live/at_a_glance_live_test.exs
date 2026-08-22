defmodule LeafWeb.AtAGlanceLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Leave

  @taken Date.range(~D[2024-10-07], ~D[2024-10-11])
  @ahead ~D[2030-10-07]
  @refused ~D[2030-10-21]

  setup %{conn: conn} do
    organisation = Fixtures.organisation()
    manager = Fixtures.person(%{organisation_id: organisation.id, name: "Ines Vasquez"})

    person =
      Fixtures.person(%{
        organisation_id: organisation.id,
        name: "Rae Halloran",
        manager_id: manager.id
      })

    Fixtures.work_pattern(%{person_id: person.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})

    Fixtures.balance_entry(%{
      person_id: person.id,
      leave_type_id: leave_type.id,
      amount: "100",
      expires_on: ~D[2030-12-31]
    })

    context = %{person: person, manager: manager, leave_type: leave_type}

    Map.put(context, :conn, sign_in(conn, person))
  end

  defp file(context, dates) do
    days =
      Enum.map(dates, fn date ->
        %{leave_type_id: context.leave_type.id, date: date, amount: "8", unit: :hours}
      end)

    {:ok, request} = Leave.request(context.person, context.person, %{days: days})
    {:ok, reloaded} = Leave.fetch_request(request.id)

    reloaded
  end

  test "somebody the session does not name is sent to pick a name" do
    assert build_conn() |> get(~p"/") |> redirected_to() == "/sign-in"
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

    assert html =~ "Monday 7 – Friday 11 October"
    assert html =~ "40 hours"
    assert html =~ "Taken"
    assert html =~ "Annual leave · approved by Ines Vasquez on"

    assert html =~ "Monday 7 October"
    assert html =~ "8 hours"
    assert html =~ "Pending"
    assert html =~ "Annual leave · sent to Ines Vasquez on"

    assert html =~ "Declined"
    assert html =~ "Ines Vasquez said Three of you are away"
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

  test "a month in the year being read in is named without it", context do
    this_year = Calendar.strftime(Date.utc_today(), "%Y-%m")
    month = Calendar.strftime(Date.utc_today(), "%B")

    {:ok, _live, html} = live(context.conn, ~p"/?from=#{this_year}")

    assert html =~ "<caption>#{month}</caption>"
  end
end
