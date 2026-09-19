defmodule LeafWeb.ApprovalsLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Leave

  @date ~D[2030-03-04]

  setup %{conn: conn} do
    workplace = Fixtures.workplace()

    Fixtures.pending_request(workplace.person, %{
      leave_type_id: workplace.leave_type.id,
      dates: [@date],
      note: "A wedding"
    })

    Map.put(workplace, :conn, conn)
  end

  test "a manager sees what their reports have asked for", context do
    {:ok, _live, html} = live(sign_in(context.conn, context.manager), ~p"/approvals")

    assert html =~ "Rae Halloran"
    assert html =~ "Monday 4 March"
    assert html =~ "A wedding"
  end

  test "a request the balance will not cover is flagged where it is decided", context do
    {:ok, _live, html} = live(sign_in(context.conn, context.manager), ~p"/approvals")

    assert html =~ ~s(data-tone="wrong")
    assert html =~ "8 hours overdrawn"
    assert html =~ "Taking leave in advance. It can still be approved."
  end

  test "a request the balance covers shows what approving leaves, and flags nothing", context do
    Fixtures.balance_entry(%{
      person_id: context.person.id,
      leave_type_id: context.leave_type.id,
      amount: "40"
    })

    {:ok, _live, html} = live(sign_in(context.conn, context.manager), ~p"/approvals")

    assert html =~ "32 hours left"
    refute html =~ "Taking leave in advance"
    refute html =~ ~s(data-tone="wrong")
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
