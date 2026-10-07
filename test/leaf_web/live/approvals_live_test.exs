defmodule LeafWeb.ApprovalsLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Leave
  alias Leaf.Ledger

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
    refute html =~ "overdrawn"
  end

  test "a request the balance will not cover is flagged where it is decided", context do
    Fixtures.balance_entry(%{
      person_id: context.person.id,
      leave_type_id: context.leave_type.id,
      amount: "5"
    })

    {:ok, _live, html} = live(sign_in(context.conn, context.manager), ~p"/approvals")

    assert html =~ ~s(data-tone="wrong")
    assert html =~ "3 hours overdrawn"
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

  test "leave far enough ahead is projected against what will have accrued by then", context do
    today = Date.utc_today()
    organisation_id = context.organisation.id
    manager = Fixtures.person(%{organisation_id: organisation_id, name: "Tomas Reid"})

    starter =
      Fixtures.person(%{
        organisation_id: organisation_id,
        manager_id: manager.id,
        employment_start_date: today
      })

    Fixtures.work_pattern(%{person_id: starter.id, effective_from: today})

    Fixtures.offering(%{
      person_id: starter.id,
      organisation_id: organisation_id,
      leave_type_id: context.leave_type.id,
      effective_from: today,
      amount_source: :fixed,
      grant_amount: "160",
      grant_basis: :employment_date,
      grant_period: :year,
      grant_timing: :daily
    })

    monday = today |> Date.add(182) |> Date.beginning_of_week()
    Fixtures.pending_request(starter, %{leave_type_id: context.leave_type.id, dates: [monday]})

    assert [%{balance: balance}] = Ledger.balances(starter, today)
    assert Decimal.lt?(balance, 8)

    {:ok, _live, html} = live(sign_in(context.conn, manager), ~p"/approvals")

    assert html =~ "hours left"
    refute html =~ "overdrawn"
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

    html = live |> element("main form") |> render_submit(%{"decision" => "approve"})

    assert html =~ "The request is approved."
    assert html =~ "Nothing is waiting on you."
    assert [%{status: :approved}] = Leave.requests(context.person)
  end

  test "the comment is a labelled textarea, so pressing Enter in it cannot decide", context do
    {:ok, live, _html} = live(sign_in(context.conn, context.manager), ~p"/approvals")

    assert has_element?(live, "form label", "Comment (optional)")
    assert has_element?(live, "form label textarea[name='review[comment]']")
    refute has_element?(live, "form input[type=text]")
  end

  test "declining carries the comment the manager typed", context do
    {:ok, live, _html} = live(sign_in(context.conn, context.manager), ~p"/approvals")

    live
    |> element("main form")
    |> render_change(%{"review" => %{"comment" => "Three of you are away"}})

    live |> element("main form") |> render_submit(%{"decision" => "decline"})

    assert [request] = Leave.requests(context.person)
    assert request.status == :declined
    assert request.review_comment == "Three of you are away"
  end
end
