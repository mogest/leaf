defmodule LeafWeb.YourRequestsLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Dates
  alias Leaf.Fixtures
  alias Leaf.Leave
  alias Leaf.Wording

  @date ~D[2040-03-05]

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
    request = file(context)

    {:ok, live, html} = live(context.conn, ~p"/leave?year=2039")

    assert html =~ "Mon 5 Mar"
    assert html =~ "1 day"
    assert html =~ "Pending"
    assert has_element?(live, ~s(th a[href="/leave/#{request.id}/amend"]))
  end

  test "cancelling a request returns what it drew", context do
    file(context)

    {:ok, live, _html} = live(context.conn, ~p"/leave?year=2039")

    html = live |> element("button", "Cancel") |> render_click()

    assert html =~ "Request cancelled."
    assert [%{status: :cancelled}] = Leave.requests(context.person)
  end

  test "a request decided after the page loaded is not cancelled", context do
    request = file(context)

    {:ok, live, _html} = live(context.conn, ~p"/leave?year=2039")

    {:ok, _approved} = Leave.approve(request, context.manager)

    assert live |> element("button", "Cancel") |> render_click() =~
             "That request was already approved."

    assert [%{status: :approved}] = Leave.requests(context.person)
  end

  test "a request over a day already spoken for is still the person's to cancel", context do
    days = [%{leave_type_id: context.leave_type.id, date: @date, amount: "8", unit: :hours}]
    both = %{person_id: context.person.id, status: :pending, days: days}
    over = Fixtures.leave_request(both)
    Fixtures.leave_request(both)

    {:ok, live, _html} = live(context.conn, ~p"/leave?year=2039")

    html = live |> element("button[phx-value-id='#{over.id}']") |> render_click()

    assert html =~ "Request cancelled."
    assert {:ok, %{status: :cancelled}} = Leave.fetch_request(over.id)
  end

  test "an approved request is not the person's to change", context do
    {:ok, _approved} = context |> file() |> Leave.approve(context.manager)

    {:ok, live, html} = live(context.conn, ~p"/leave?year=2039")

    assert html =~ "Approved"
    refute has_element?(live, "th a")
    refute has_element?(live, "td button")
  end

  test "requests are shown a financial year at a time, of one leave type or all", context do
    file(context)
    sick = Fixtures.leave_type(%{organisation_id: context.organisation.id, name: "Sick leave"})

    Fixtures.leave_request(%{
      person_id: context.person.id,
      days: [%{leave_type_id: sick.id, date: ~D[2040-04-09], amount: "1", unit: :days}]
    })

    {:ok, live, html} = live(context.conn, ~p"/leave")
    this_year = Dates.year(Dates.year_of(Date.utc_today(), 4), 4)

    assert html =~ "#{Wording.date(this_year.first)} – #{Wording.date(this_year.last)}"
    assert html =~ "No leave requests in this year."
    refute has_element?(live, "a[aria-label='Earlier year']")

    {:ok, live, html} = live(context.conn, ~p"/leave?year=2039")

    assert html =~ "Mon 5 Mar"
    refute html =~ "Mon 9 Apr"
    assert has_element?(live, ~s(a[href="/leave?year=2040"]))

    html = live |> form("#filter", filter: %{leave_type: sick.id}) |> render_change()

    assert_patch(live, ~p"/leave?leave_type=#{sick.id}&year=2039")
    assert html =~ "No leave requests in this year."

    {:ok, _live, html} =
      live
      |> element("a[aria-label='Later year']")
      |> render_click()
      |> follow_redirect(context.conn)

    assert html =~ "Mon 9 Apr"
    refute html =~ "Mon 5 Mar"
  end
end
