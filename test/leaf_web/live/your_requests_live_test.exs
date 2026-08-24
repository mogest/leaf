defmodule LeafWeb.YourRequestsLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Leave

  @date ~D[2030-03-04]

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

    Fixtures.offering(%{
      person_id: person.id,
      organisation_id: organisation.id,
      leave_type_id: leave_type.id
    })

    %{
      conn: sign_in(conn, person),
      person: person,
      manager: manager,
      leave_type: leave_type
    }
  end

  defp file(context) do
    days = [%{leave_type_id: context.leave_type.id, date: @date, amount: "8", unit: :hours}]
    {:ok, request} = Leave.request(context.person, context.person, %{days: days})
    {:ok, filed} = Leave.fetch_request(request.id)

    filed
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
