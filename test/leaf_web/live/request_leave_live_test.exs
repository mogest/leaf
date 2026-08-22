defmodule LeafWeb.RequestLeaveLiveTest do
  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.Leave

  @week Date.range(~D[2026-03-02], ~D[2026-03-06])
  @monday ~D[2026-03-02]
  @sunday ~D[2026-03-08]

  setup %{conn: conn} do
    organisation = Fixtures.organisation()
    person = Fixtures.person(%{organisation_id: organisation.id})
    Fixtures.work_pattern(%{person_id: person.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})
    policy = Fixtures.leave_policy(%{organisation_id: organisation.id})

    Fixtures.policy_entitlement(%{leave_policy_id: policy.id, leave_type_id: leave_type.id})
    Fixtures.policy_assignment(%{person_id: person.id, leave_policy_id: policy.id})

    %{conn: sign_in(conn, person), person: person, leave_type: leave_type}
  end

  defp asking(context, params) do
    Map.merge(
      %{
        "leave_type_id" => context.leave_type.id,
        "from" => to_string(@monday),
        "to" => to_string(@monday),
        "amount" => "",
        "unit" => "hours",
        "note" => ""
      },
      params
    )
  end

  test "only the leave types the person's policy offers can be asked for", context do
    other = Fixtures.leave_type(%{organisation_id: context.person.organisation_id, position: 2})

    {:ok, _live, html} = live(context.conn, ~p"/leave/new")

    assert html =~ "Annual leave (in hours)"
    refute html =~ other.id
  end

  test "the days that will be filed are the working days in the range", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live
      |> form("form", request: asking(context, %{"to" => to_string(@sunday)}))
      |> render_change()

    assert html =~ "5 working days"
    assert html =~ "Monday 2 March"
    assert html =~ "Friday 6 March"
    refute html =~ "Saturday 7 March"
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

  test "an amount is taken in the unit it is counted in", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    live
    |> form("form", request: asking(context, %{"amount" => "1.8", "unit" => "hours"}))
    |> render_submit()

    assert [%{days: [day]}] = Leave.requests(context.person)
    assert day.unit == :hours
    assert Decimal.equal?(day.amount, "1.8")
  end

  test "an amount that is not a number is refused before anything is filed", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    html =
      live |> form("form", request: asking(context, %{"amount" => "half"})) |> render_change()

    assert html =~ "The amount per day has to be a number."
    assert Leave.requests(context.person) == []
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
end
