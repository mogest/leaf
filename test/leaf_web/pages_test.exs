defmodule LeafWeb.PagesTest do
  @moduledoc """
  Every page, against the example organisation, as an administrator.

  The seed is the one place a whole configured organisation exists — two policies, a real holiday
  calendar, people on both — so it is what catches a page that only works against a fixture with
  nothing in it.
  """

  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Leave
  alias Leaf.Org
  alias Leaf.People
  alias Leaf.Policies
  alias Leaf.Seed

  setup %{conn: conn} do
    %{organisation: organisation, people: people, policies: policies} = Seed.run()
    admin = people["Mog"]
    [leave_type | _rest] = Policies.leave_types(organisation.id)
    [calendar | _rest] = Org.holiday_calendars(organisation.id)
    [pattern | _rest] = People.work_patterns(admin)
    [entitlement | _rest] = Policies.entitlements(policies["New Zealand employee"].id)

    %{
      conn: sign_in(conn, admin),
      admin: admin,
      other: people["Ari Kelburn"],
      leave_type: leave_type,
      calendar: calendar,
      pattern: pattern,
      policy: policies["New Zealand employee"],
      entitlement: entitlement
    }
  end

  defp paths(context) do
    [
      ~p"/",
      ~p"/leave",
      ~p"/leave/new",
      ~p"/approvals",
      ~p"/away",
      ~p"/people",
      ~p"/people/new",
      ~p"/people/#{context.admin}",
      ~p"/people/#{context.admin}/edit",
      ~p"/people/#{context.other}",
      ~p"/people/#{context.admin}/balances/#{context.leave_type}",
      ~p"/people/#{context.admin}/work-patterns/new",
      ~p"/people/#{context.admin}/work-patterns/#{context.pattern}",
      ~p"/people/#{context.admin}/policy-assignments/new",
      ~p"/people/#{context.admin}/calendar-assignments/new",
      ~p"/people/#{context.admin}/balance-entries/new",
      ~p"/settings",
      ~p"/settings/leave-types",
      ~p"/settings/leave-types/#{context.leave_type}",
      ~p"/settings/policies",
      ~p"/settings/policies/#{context.policy}",
      ~p"/settings/policies/#{context.policy}/entitlements/new",
      ~p"/settings/policies/#{context.policy}/entitlements/#{context.entitlement}",
      ~p"/settings/calendars",
      ~p"/settings/calendars/#{context.calendar}",
      ~p"/settings/audit"
    ]
  end

  test "every page renders", context do
    Enum.each(paths(context), fn path ->
      assert {:ok, _live, html} = live(context.conn, path)
      assert html =~ "Fernbank Collective" or html =~ "<h1>"
    end)
  end

  test "the specimen sheet renders every part the pages are built from", context do
    {:ok, _live, html} = live(context.conn, "/dev/styleguide")

    assert html =~ "Specimen sheet"
    assert html =~ "Palette"
    assert html =~ ~s(class="tabs")
    assert html =~ ~s(class="legend")
    assert html =~ "has to be a number"
  end

  test "a request filed on the site reaches the queue and the calendar", context do
    {:ok, live, _html} = live(context.conn, ~p"/leave/new")

    live
    |> form("#request",
      request: %{
        "leave_type_id" => context.leave_type.id,
        "from" => "2030-10-07",
        "to" => "2030-10-11",
        "note" => ""
      }
    )
    |> render_submit()

    assert [request] = Leave.requests(context.admin)
    assert length(request.days) == 4

    {:ok, _live, html} = live(context.conn, ~p"/approvals")
    assert html =~ "one request waiting"

    {:ok, _live, html} = live(context.conn, ~p"/away?month=2030-10")
    assert html =~ ~s(data-leave="pending")
  end
end
