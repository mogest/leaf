defmodule LeafWeb.RequestLeaveLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Leave
  alias Leaf.People
  alias Leaf.Policies

  @week Date.range(~D[2026-03-02], ~D[2026-03-06])
  @monday ~D[2026-03-02]
  @friday ~D[2026-03-06]
  @saturday ~D[2026-03-07]
  @sunday ~D[2026-03-08]
  @next_monday ~D[2026-03-09]

  setup %{conn: conn} do
    organisation = Fixtures.organisation()
    person = Fixtures.person(%{organisation_id: organisation.id})
    Fixtures.work_pattern(%{person_id: person.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})
    policy = Fixtures.leave_policy(%{organisation_id: organisation.id})

    entitlement =
      Fixtures.policy_entitlement(%{leave_policy_id: policy.id, leave_type_id: leave_type.id})

    Fixtures.policy_assignment(%{person_id: person.id, leave_policy_id: policy.id})

    %{
      conn: sign_in(conn, person),
      person: person,
      leave_type: leave_type,
      policy: policy,
      entitlement: entitlement
    }
  end

  defp closed_on(context, date) do
    {:ok, _entitlement} =
      Policies.update_entitlement(context.entitlement, nil, %{effective_to: date})
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

  # Part of a day is asked of one day, so the field is only there once a single day has been entered.
  defp asking_hours(live, context, params) do
    live |> form("#request", request: asking(context, %{})) |> render_change()
    live |> form("#request", request: asking(context, params))
  end

  # Dates are entered while a type is already chosen, so the change carries the choice the options
  # before it offered rather than one of the options the new dates offer.
  defp dating(live, context, params) do
    render_change(live, "validate", %{"request" => asking(context, params)})
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

  # A type the policy records and grants nothing in, so anything filed against it goes negative.
  defp unfunded(context, attrs) do
    leave_type =
      Fixtures.leave_type(Map.put(attrs, :organisation_id, context.person.organisation_id))

    Fixtures.policy_entitlement(%{
      leave_policy_id: context.policy.id,
      leave_type_id: leave_type.id,
      amount_source: :none,
      grant_amount: nil,
      grant_basis: nil,
      grant_period: nil,
      grant_timing: nil
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

  test "a type whose entitlement has closed is offered for the dates it covered", context do
    closed_on(context, @friday)

    {:ok, live, html} = live(context.conn, ~p"/leave/new")

    refute html =~ "Annual leave"
    assert dating(live, context, %{"to" => to_string(@friday)}) =~ "Annual leave"

    live
    |> form("#request", request: asking(context, %{"to" => to_string(@friday)}))
    |> render_submit()

    assert [%{days: days}] = Leave.requests(context.person)
    assert Enum.map(days, & &1.date) == Enum.to_list(@week)
  end

  test "a type dated outside what it was offered over says so", context do
    closed_on(context, @friday)

    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    dated = %{"from" => to_string(@next_monday), "to" => to_string(@next_monday)}

    assert dating(live, context, dated) =~ "That leave type isn&#39;t available on those dates."
  end

  test "the dates start blank, and a last day left blank asks for the first day alone", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    refute has_element?(live, "#request_from[value]")
    refute has_element?(live, "#request_to[value]")

    live |> form("#request", request: asking(context, %{"to" => ""})) |> render_submit()

    assert [%{days: [day]}] = Leave.requests(context.person)
    assert day.date == @monday
  end

  test "leaving one date fills in the other, and drags it where it is the wrong side", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    live |> form("#request", request: asking(context, %{"to" => ""})) |> render_change()
    live |> element("#request_from") |> render_blur()

    assert has_element?(live, "#request_to[value='#{@monday}']")

    live
    |> form("#request", request: asking(context, %{"from" => to_string(@next_monday)}))
    |> render_change()

    live |> element("#request_from") |> render_blur()

    assert has_element?(live, "#request_to[value='#{@next_monday}']")

    live
    |> form("#request", request: asking(context, %{"from" => to_string(@friday)}))
    |> render_change()

    live |> element("#request_to") |> render_blur()

    assert has_element?(live, "#request_from[value='#{@monday}']")
  end

  test "the days that will be filed are the working days in the range", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("#request", request: asking(context, %{"to" => to_string(@sunday)}))
      |> render_change()

    assert html =~ "Mon 2 Mar"
    assert html =~ "Fri 6 Mar"
    assert html =~ "Sun 8 Mar"
    assert html =~ "<td>40 hours</td>"
  end

  test "a stretch is shown even where only one day in it is worked", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("#request",
        request:
          asking(context, %{"from" => to_string(@saturday), "to" => to_string(@next_monday)})
      )
      |> render_change()

    assert html =~ "Sat 7 Mar"
    assert html =~ "Mon 9 Mar"
    assert html =~ "<td>8 hours</td>"
  end

  test "the days a stretch steps over are rows of their own", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("#request",
        request: asking(context, %{"from" => to_string(@friday), "to" => to_string(@next_monday)})
      )
      |> render_change()

    assert html =~ ~s(<tr data-working="no">)
    assert html =~ "Sat 7 Mar"
    assert html =~ "not worked"
    assert html =~ "<td>16 hours</td>"
  end

  test "leave short of a checked balance says only an administrator can approve it", context do
    training =
      Fixtures.leave_type(%{
        organisation_id: context.person.organisation_id,
        name: "Training leave",
        position: 2
      })

    Fixtures.policy_entitlement(%{
      leave_policy_id: context.policy.id,
      leave_type_id: training.id,
      grant_amount: "0",
      balance_check: :projected
    })

    Fixtures.balance_entry(%{
      person_id: context.person.id,
      leave_type_id: training.id,
      amount: "8"
    })

    Fixtures.pending_request(context.person, %{leave_type_id: training.id, dates: [@monday]})

    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    friday =
      asking(context, %{
        "leave_type_id" => training.id,
        "from" => "#{@friday}",
        "to" => "#{@friday}"
      })

    html = live |> form("#request", request: friday) |> render_change()

    assert html =~ "Counting the other requests still awaiting approval"
    refute html =~ "It can still be approved."

    week =
      asking(context, %{
        "leave_type_id" => training.id,
        "from" => "#{Date.add(@monday, 1)}",
        "to" => "#{@friday}"
      })

    html = live |> form("#request", request: week) |> render_change()

    assert html =~
             "Today&#39;s balance doesn&#39;t cover this. It needs an administrator to approve it."

    refute html =~ "It can still be approved."
  end

  test "one day has no rows worth reading, and still says what it would leave", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html = live |> form("#request", request: asking(context, %{})) |> render_change()

    refute html =~ "Day by day"
    assert html =~ "Annual leave on"
    assert html =~ "Without this request"
    assert html =~ "Send the request"
  end

  test "leave the balance will not cover says so, and leave with no balance says nothing",
       context do
    unpaid = unfunded(context, %{name: "Unpaid leave", position: 2})
    bereavement = unfunded(context, %{name: "Bereavement leave", position: 3})

    Fixtures.balance_entry(%{
      person_id: context.person.id,
      leave_type_id: bereavement.id,
      amount: "4"
    })

    Fixtures.leave_request(%{
      person_id: context.person.id,
      days: [%{leave_type_id: unpaid.id, date: @friday, amount: "8", unit: :hours}]
    })

    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("#request", request: asking(context, %{"leave_type_id" => unpaid.id}))
      |> render_change()

    refute html =~ "Unpaid leave —"
    refute has_element?(live, "h2", "Balance")

    asked = asking(context, %{"leave_type_id" => bereavement.id})
    html = live |> form("#request", request: asked) |> render_change()

    assert has_element?(live, "dd", ~r/^\s*4 hours\s*$/)
    assert has_element?(live, ~s(dd[data-tone="wrong"]), "-4 hours")
    assert html =~ "That is more leave than the balance holds. It can still be approved."

    live |> form("#request", request: asked) |> render_submit()

    assert [%{status: :approved}, %{status: :pending}] = Leave.requests(context.person)
  end

  test "a range with nothing workable in it says so and files nothing", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("#request",
        request: asking(context, %{"from" => to_string(@sunday), "to" => to_string(@sunday)})
      )
      |> render_change()

    assert html =~ "Sunday 8 March is not a working day."

    html =
      live
      |> form("#request",
        request: asking(context, %{"from" => to_string(@saturday), "to" => to_string(@sunday)})
      )
      |> render_change()

    assert html =~ "None of those days is a working day."
  end

  test "an unfilled form is not reported back to whoever has not filled it in", context do
    {:ok, live, html} = live(context.conn, ~p"/leave/new")

    refute html =~ "Day by day"

    html =
      live
      |> form("#request", request: asking(context, %{"from" => "", "to" => ""}))
      |> render_change()

    refute html =~ "Day by day"
    refute html =~ "Give a first day."
  end

  test "filing a request files a day for each working day, pending", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    live
    |> form("#request", request: asking(context, %{"to" => to_string(@sunday), "note" => "Away"}))
    |> render_submit()

    assert [request] = Leave.requests(context.person)
    assert request.status == :pending
    assert request.note == "Away"
    assert Enum.map(request.days, & &1.date) == Enum.to_list(@week)
    assert Enum.all?(request.days, &(&1.unit == :days and Decimal.equal?(&1.amount, 1)))
  end

  test "part of a day is asked in what its leave type counts in", context do
    sick = sick_leave(context)

    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html = live |> asking_hours(context, %{}) |> render_change()

    assert html =~ "Hours off"
    assert html =~ "the whole day (8 hours)"

    params = %{"leave_type_id" => sick.id, "amount" => "0.5"}
    html = live |> asking_hours(context, params) |> render_change()

    assert html =~ "Days off"
    assert html =~ "the whole day (1 day)"
    refute html =~ "Day by day"

    live |> form("#request", request: asking(context, params)) |> render_submit()

    assert [%{days: [part]}] = Leave.requests(context.person)
    assert part.unit == :days
    assert Decimal.equal?(part.amount, "0.5")
  end

  test "part of a day is not asked of a stretch of days", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> asking_hours(context, %{"to" => to_string(@friday), "amount" => "4"})
      |> render_change()

    assert html =~ "Part days can only be requested for a single day."
    refute has_element?(live, ~s(input[name="request[amount]"]))
    assert Leave.requests(context.person) == []
  end

  test "hours that are not a number are refused before anything is filed", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html = live |> asking_hours(context, %{"amount" => "half"}) |> render_change()

    assert html =~ "Enter a number."
    assert Leave.requests(context.person) == []
  end

  test "more hours than the day holds are refused", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html = live |> asking_hours(context, %{"amount" => "9"}) |> render_change()

    assert html =~ "Monday 2 March has only 8 hours free."
    assert Leave.requests(context.person) == []
  end

  test "a day already spoken for is refused before anything is filed again", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    live
    |> form("#request", request: asking(context, %{"to" => to_string(@friday)}))
    |> render_submit()

    {:ok, again, _html} = live(context.conn, ~p"/leave/new")

    friday = %{"from" => to_string(@friday), "to" => to_string(@friday)}

    html = again |> form("#request", request: asking(context, friday)) |> render_change()

    assert html =~ "Friday 6 March already has leave on it."
    assert [_first] = Leave.requests(context.person)
  end

  test "what the one leave type asked for would be left with is shown", context do
    sick = sick_leave(context)

    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("#request",
        request: asking(context, %{"leave_type_id" => sick.id, "to" => to_string(@friday)})
      )
      |> render_change()

    assert html =~ "Sick leave on"
    assert html =~ "25 days"
    assert has_element?(live, "tfoot td", "5 days")
    refute html =~ "Annual leave on"
  end

  test "a request with no days to file says so rather than coming back silent", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("#request", request: asking(context, %{"leave_type_id" => "", "to" => ""}))
      |> render_submit()

    assert html =~ "The request couldn&#39;t be saved. Check the details and try again."
    assert Leave.requests(context.person) == []
  end

  test "the form says who decides the request", context do
    {:ok, _live, html} = live(context.conn, ~p"/leave/new")
    assert html =~ "Your leave will be reviewed by an administrator"

    manager =
      Fixtures.person(%{organisation_id: context.person.organisation_id, name: "Ines Vasquez"})

    {:ok, _person} = People.update_person(context.person, nil, %{manager_id: manager.id})

    {:ok, live, html} = live(context.conn, ~p"/leave/new")
    assert html =~ "Your leave will be reviewed by Ines Vasquez"

    {:ok, _type} = Policies.update_leave_type(context.leave_type, nil, %{needs_approval: false})

    assert live |> form("#request", request: asking(context, %{})) |> render_change() =~
             "Your leave doesn&#39;t need approval, so it&#39;s approved as soon as it&#39;s sent"
  end

  test "a request that is no longer open to change is not there to edit", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")
    live |> form("#request", request: asking(context, %{})) |> render_submit()
    [request] = Leave.requests(context.person)
    {:ok, _cancelled} = Leave.cancel(request, context.person)

    for id <- [request.id, Ecto.UUID.generate(), "banana"] do
      assert {:error, {:live_redirect, %{to: "/leave", flash: flash}}} =
               live(context.conn, ~p"/leave/#{id}/amend")

      assert flash["error"] == "You can't edit that request."
    end
  end

  test "a request cancelled after its amendment was opened is not saved", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")
    live |> form("#request", request: asking(context, %{})) |> render_submit()
    [request] = Leave.requests(context.person)

    {:ok, amend, _html} = live(context.conn, ~p"/leave/#{request}/amend")
    {:ok, _cancelled} = Leave.cancel(request, context.person)

    {:ok, _live, html} =
      amend
      |> form("#request", request: asking(context, %{"to" => to_string(@friday)}))
      |> render_submit()
      |> follow_redirect(context.conn, ~p"/leave")

    assert html =~ "That request was already cancelled."

    assert [%{status: :cancelled}] = Leave.requests(context.person)
  end

  test "amending replaces the days a pending request asks for", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")
    live |> form("#request", request: asking(context, %{})) |> render_submit()
    [request] = Leave.requests(context.person)

    # Amending does not approve, so a pending request stays one whatever its type now says.
    {:ok, _type} = Policies.update_leave_type(context.leave_type, nil, %{needs_approval: false})
    {:ok, amend, html} = live(context.conn, ~p"/leave/#{request}/amend")

    assert html =~ "Edit a request"
    assert html =~ "Your leave will be reviewed by an administrator"

    amend
    |> form("#request", request: asking(context, %{"to" => to_string(@sunday)}))
    |> render_submit()

    assert [%{id: same, days: days, status: :pending}] = Leave.requests(context.person)
    assert same == request.id
    assert length(days) == 5
  end

  test "a manager amends a report's approved request from their page and lands back there",
       context do
    manager =
      Fixtures.person(%{organisation_id: context.person.organisation_id, name: "Ines Vasquez"})

    {:ok, person} = People.update_person(context.person, nil, %{manager_id: manager.id})
    conn = sign_in(context.conn, manager)

    {:ok, request} =
      Leave.request(person, person, %{
        days: [%{leave_type_id: context.leave_type.id, date: @monday, amount: "8", unit: :hours}]
      })

    {:ok, _amend, html} = live(conn, ~p"/leave/#{request}/amend")
    assert html =~ "Rae Halloran&#39;s leave will be reviewed by Ines Vasquez"

    {:ok, _approved} = Leave.approve(request, manager)

    {:ok, page, _html} = live(conn, ~p"/people/#{person}")
    assert has_element?(page, ~s(th a[href="/leave/#{request.id}/amend"]))

    {:ok, amend, html} = live(conn, ~p"/leave/#{request}/amend")
    assert has_element?(amend, ~s(a[href="/people/#{person.id}"]), "Cancel")
    refute html =~ "leave will be reviewed by"

    assert dating(amend, context, %{"from" => to_string(@saturday), "to" => to_string(@saturday)}) =~
             "Saturday 7 March is not a working day."

    assert {:error, {:live_redirect, %{to: to}}} =
             amend
             |> form("#request",
               request:
                 asking(context, %{"from" => to_string(@friday), "to" => to_string(@friday)})
             )
             |> render_submit()

    assert to == "/people/#{person.id}"
    assert [%{status: :approved, days: [%{date: @friday}]}] = Leave.requests(person)
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

    assert html =~ "Mon 2 Mar"
    assert html =~ "Tue 3 Mar"
    assert html =~ "<td>16 hours</td>"
    assert html =~ "are not a whole day of this leave type."
    assert html =~ "Saving changes the request to match."
  end

  test "amending part of a day starts from it, in its leave type's unit", context do
    sick = sick_leave(context)

    {:ok, request} =
      Leave.request(context.person, context.person, %{
        days: [%{leave_type_id: sick.id, date: @monday, amount: "0.5", unit: :days}]
      })

    {:ok, amend, html} = live(context.conn, ~p"/leave/#{request}/amend")

    assert has_element?(amend, ~s(input[name="request[amount]"][value="0.50"]))
    refute html =~ "are not a whole day of this leave type."
  end

  # Before a type counted in days was always held in days, the form filed its part days in hours.
  test "amending sick leave held in hours says saving replaces it", context do
    sick = sick_leave(context)

    request =
      Fixtures.leave_request(%{
        person_id: context.person.id,
        status: :pending,
        days: [%{leave_type_id: sick.id, date: @monday, amount: "4", unit: :hours}]
      })

    {:ok, _amend, html} = live(context.conn, ~p"/leave/#{request.id}/amend")

    assert html =~ "are not a whole day of this leave type."
  end
end
