defmodule LeafWeb.ApprovalsLiveTest do
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
    days = [%{leave_type_id: leave_type.id, date: @date, amount: "8", unit: :hours}]
    {:ok, _request} = Leave.request(person, person, %{days: days, note: "A wedding"})

    %{conn: conn, organisation: organisation, manager: manager, person: person}
  end

  test "a manager sees what their reports have asked for", context do
    {:ok, _live, html} = live(sign_in(context.conn, context.manager), ~p"/approvals")

    assert html =~ "one request waiting"
    assert html =~ "Rae Halloran"
    assert html =~ "Monday 4 March"
    assert html =~ "A wedding"
  end

  test "somebody with no reports has nothing waiting on them", context do
    {:ok, _live, html} = live(sign_in(context.conn, context.person), ~p"/approvals")

    assert html =~ "Nothing is waiting on you."
  end

  test "only somebody with approvals to make is offered them", context do
    {:ok, _live, manager} = live(sign_in(context.conn, context.manager), ~p"/")
    {:ok, _live, member} = live(sign_in(context.conn, context.person), ~p"/")

    assert manager =~ ~s(href="/approvals")
    refute member =~ ~s(href="/approvals")
  end

  test "an administrator decides for the whole organisation", context do
    admin =
      Fixtures.person(%{organisation_id: context.organisation.id, name: "Kit Rua", role: :admin})

    {:ok, _live, html} = live(sign_in(context.conn, admin), ~p"/approvals")

    assert html =~ "Rae Halloran"
  end

  test "approving takes the request off the queue", context do
    {:ok, live, _html} = live(sign_in(context.conn, context.manager), ~p"/approvals")

    html = live |> element("form") |> render_submit(%{"decision" => "approve"})

    assert html =~ "The request is approved."
    assert html =~ "Nothing is waiting on you."
    assert [%{status: :approved}] = Leave.requests(context.person)
  end

  test "declining carries the comment the manager typed", context do
    {:ok, live, _html} = live(sign_in(context.conn, context.manager), ~p"/approvals")

    live
    |> element("form")
    |> render_submit(%{"decision" => "decline", "comment" => "Three of you are away"})

    assert [request] = Leave.requests(context.person)
    assert request.status == :declined
    assert request.review_comment == "Three of you are away"
  end
end
