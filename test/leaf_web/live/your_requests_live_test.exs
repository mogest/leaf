defmodule LeafWeb.YourRequestsLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Leave

  @date ~D[2030-03-04]

  setup %{conn: conn} do
    workplace = Fixtures.workplace()
    Map.put(workplace, :conn, sign_in(conn, workplace.person))
  end

  defp file(context) do
    Fixtures.pending_request(context.person, %{
      leave_type_id: context.leave_type.id,
      dates: [@date]
    })
  end

  test "every request is listed, with what can still be done to a pending one", context do
    file(context)

    {:ok, _live, html} = live(context.conn, ~p"/leave")

    assert html =~ "Mon 4 Mar"
    assert html =~ "8 hours"
    assert html =~ "Pending"
    assert html =~ ">Edit<"
  end

  test "cancelling a request returns what it drew", context do
    file(context)

    {:ok, live, _html} = live(context.conn, ~p"/leave")

    html = live |> element("button", "Cancel") |> render_click()

    assert html =~ "The request is cancelled."
    assert [%{status: :cancelled}] = Leave.requests(context.person)
  end

  test "a request over a day already spoken for is still the person's to cancel", context do
    days = [%{leave_type_id: context.leave_type.id, date: @date, amount: "8", unit: :hours}]
    both = %{person_id: context.person.id, status: :pending, days: days}
    over = Fixtures.leave_request(both)
    Fixtures.leave_request(both)

    {:ok, live, _html} = live(context.conn, ~p"/leave")

    html = live |> element("button[phx-value-id='#{over.id}']") |> render_click()

    assert html =~ "The request is cancelled."
    assert {:ok, %{status: :cancelled}} = Leave.fetch_request(over.id)
  end

  test "an approved request is not the person's to change", context do
    {:ok, _approved} = context |> file() |> Leave.approve(context.manager)

    {:ok, _live, html} = live(context.conn, ~p"/leave")

    assert html =~ "Approved"
    refute html =~ ">Edit<"
  end
end
