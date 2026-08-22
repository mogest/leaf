defmodule LeafWeb.RequestLeaveLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Leave

  @week Date.range(~D[2026-03-02], ~D[2026-03-06])
  @monday ~D[2026-03-02]
  @friday ~D[2026-03-06]
  @sunday ~D[2026-03-08]
  @next_monday ~D[2026-03-09]

  setup %{conn: conn} do
    organisation = Fixtures.organisation()
    person = Fixtures.person(%{organisation_id: organisation.id})
    Fixtures.work_pattern(%{person_id: person.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})
    policy = Fixtures.leave_policy(%{organisation_id: organisation.id})

    Fixtures.policy_entitlement(%{leave_policy_id: policy.id, leave_type_id: leave_type.id})
    Fixtures.policy_assignment(%{person_id: person.id, leave_policy_id: policy.id})

    %{conn: sign_in(conn, person), person: person, leave_type: leave_type, policy: policy}
  end

  defp asking(context, params) do
    Map.merge(
      %{
        "leave_type_id" => context.leave_type.id,
        "from" => to_string(@monday),
        "to" => to_string(@monday),
        "note" => ""
      },
      params
    )
  end

  # Hours off are asked of a day, so the field is only there once a single day has been entered.
  defp asking_hours(live, context, params) do
    live |> form("form", request: asking(context, %{})) |> render_change()
    live |> form("form", request: asking(context, params))
  end

  # A second type on the same policy, counted in days where annual leave is counted in hours.
  defp sick_leave(context) do
    leave_type =
      Fixtures.leave_type(%{
        organisation_id: context.person.organisation_id,
        name: "Sick leave",
        unit: :days,
        position: 2
      })

    Fixtures.policy_entitlement(%{
      leave_policy_id: context.policy.id,
      leave_type_id: leave_type.id,
      grant_amount: "10",
      grant_timing: :period_start,
      pro_rated_by_fte: false
    })

    leave_type
  end

  test "a leave type is offered with what is left in it, and only where the policy offers it",
       context do
    other = Fixtures.leave_type(%{organisation_id: context.person.organisation_id, position: 2})

    {:ok, _live, html} = live(context.conn, ~p"/leave/new")

    assert html =~ "Annual leave —"
    assert html =~ "hours left"
    refute html =~ other.id
  end

  test "the dates start blank, and a last day left blank asks for the first day alone", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    refute has_element?(live, "#request_from[value]")
    refute has_element?(live, "#request_to[value]")

    html = live |> form("form", request: asking(context, %{"to" => ""})) |> render_change()

    assert html =~ "Monday 2 March: 1 day of annual leave."
    assert has_element?(live, "#request_to[value='']")
  end

  test "leaving one date fills in the other, and drags it where it is the wrong side", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    live |> form("form", request: asking(context, %{"to" => ""})) |> render_change()
    live |> element("#request_from") |> render_blur()

    assert has_element?(live, "#request_to[value='#{@monday}']")

    live
    |> form("form", request: asking(context, %{"from" => to_string(@next_monday)}))
    |> render_change()

    live |> element("#request_from") |> render_blur()

    assert has_element?(live, "#request_to[value='#{@next_monday}']")

    live
    |> form("form", request: asking(context, %{"from" => to_string(@friday)}))
    |> render_change()

    live |> element("#request_to") |> render_blur()

    assert has_element?(live, "#request_from[value='#{@monday}']")
  end

  test "the days that will be filed are the working days in the range", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("form", request: asking(context, %{"to" => to_string(@sunday)}))
      |> render_change()

    assert html =~ "Monday 2 – Friday 6 March: 5 working days"
    assert html =~ "coming to 5 days of annual leave."
  end

  test "the days a stretch steps over are counted", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("form",
        request: asking(context, %{"from" => to_string(@friday), "to" => to_string(@next_monday)})
      )
      |> render_change()

    assert html =~ "Friday 6 – Monday 9 March: 2 working days"
    assert html =~ "Passing over 2 days you do not work."
  end

  test "a range with nothing workable in it says so and files nothing", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("form",
        request: asking(context, %{"from" => to_string(@sunday), "to" => to_string(@sunday)})
      )
      |> render_change()

    assert html =~ "Not one of those dates is a day you work."
    assert html =~ "Nothing can be filed as it stands."
  end

  test "nothing is asked of somebody who has not chosen a leave type yet", context do
    {:ok, _live, html} = live(context.conn, ~p"/leave/new")

    assert html =~ "Nothing yet — choose a leave type and the days you want off."
    refute html =~ "Choose a leave type."
  end

  test "filing a request files a day for each working day, pending", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    live
    |> form("form", request: asking(context, %{"to" => to_string(@sunday), "note" => "Away"}))
    |> render_submit()

    assert [request] = Leave.requests(context.person)
    assert request.status == :pending
    assert request.note == "Away"
    assert Enum.map(request.days, & &1.date) == Enum.to_list(@week)
    assert Enum.all?(request.days, &(&1.unit == :days and Decimal.equal?(&1.amount, 1)))
  end

  test "part of a day is asked in hours, whatever its leave type counts in", context do
    sick = sick_leave(context)

    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    params = %{"leave_type_id" => sick.id, "amount" => "4"}
    html = live |> asking_hours(context, params) |> render_change()

    assert html =~ "the whole day (8 hours)"
    assert html =~ "Monday 2 March: 4 hours of sick leave."
    assert html =~ "Sick leave: 30 days → 29.5 days if it is approved."

    live |> form("form", request: asking(context, params)) |> render_submit()

    assert [%{days: [part]}] = Leave.requests(context.person)
    assert part.unit == :hours
    assert Decimal.equal?(part.amount, 4)
  end

  test "hours off are not asked of a stretch of days", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> asking_hours(context, %{"to" => to_string(@friday), "amount" => "4"})
      |> render_change()

    assert html =~ "Hours off can only be asked of a single day."
    refute html =~ "Hours off</span>"
    assert Leave.requests(context.person) == []
  end

  test "hours that are not a number are refused before anything is filed", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html = live |> asking_hours(context, %{"amount" => "half"}) |> render_change()

    assert html =~ "The hours off have to be a number."
    assert Leave.requests(context.person) == []
  end

  test "more hours than the day holds are refused", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html = live |> asking_hours(context, %{"amount" => "9"}) |> render_change()

    assert html =~ "You only work 8 hours on Monday 2 March."
    assert Leave.requests(context.person) == []
  end

  test "the one balance that moves is shown as it stands and as it would be", context do
    sick = sick_leave(context)

    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("form", request: asking(context, %{"leave_type_id" => sick.id}))
      |> render_change()

    assert html =~ "Monday 2 March: 1 day of sick leave."
    assert html =~ "Sick leave: 30 days → 29 days if it is approved."
    refute html =~ "Annual leave:"
  end

  test "amending replaces the days a pending request asks for", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")
    live |> form("form", request: asking(context, %{})) |> render_submit()
    [request] = Leave.requests(context.person)

    {:ok, amend, html} = live(context.conn, ~p"/leave/#{request}/amend")

    assert html =~ "Amend a request"

    amend
    |> form("form", request: asking(context, %{"to" => to_string(@sunday)}))
    |> render_submit()

    assert [%{id: same, days: days}] = Leave.requests(context.person)
    assert same == request.id
    assert length(days) == 5
  end

  test "amending days this cannot say says what would replace them", context do
    {:ok, request} =
      Leave.request(context.person, context.person, %{
        days: [
          %{
            leave_type_id: context.leave_type.id,
            date: @monday,
            amount: Decimal.new(2),
            unit: :hours
          },
          %{
            leave_type_id: context.leave_type.id,
            date: Date.add(@monday, 1),
            amount: Decimal.new(3),
            unit: :hours
          }
        ]
      })

    {:ok, _amend, html} = live(context.conn, ~p"/leave/#{request}/amend")

    assert html =~ "Monday 2 – Tuesday 3 March: 2 working days, coming to 2 days of annual leave."
    assert html =~ "Those days do not all ask for the whole day."
    assert html =~ "Saving this replaces what they ask for."
  end
end
