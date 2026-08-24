defmodule LeafWeb.PagesTest do
  @moduledoc """
  Every page, against the example organisation, as an administrator and as a member.

  The seed is the one place a whole configured organisation exists — two policies, a real holiday
  calendar, people on both — so it is what catches a page that only works against a fixture with
  nothing in it.

  The member's pass is the other half: every page the administrator's live session holds turns them
  away, and every page that is theirs still renders. What they may *do* on a page they may open is
  `LeafWeb.AuthorizedEvents`' to say, and it will not compile an event that does not say it.
  """

  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Leave
  alias Leaf.Org
  alias Leaf.People
  alias Leaf.Policies
  alias Leaf.Seed

  setup %{conn: conn} do
    {:ok, %{organisation: organisation, people: people, policies: policies}} = Seed.run()
    admin = people["Mog"]
    [leave_type | _rest] = Policies.leave_types(organisation.id)
    [calendar | _rest] = Org.calendars(organisation.id)
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

  # The pages anybody signed in may open, read as `who`.
  defp theirs(context, who) do
    [
      ~p"/",
      ~p"/leave",
      ~p"/leave/new",
      ~p"/approvals",
      ~p"/away",
      ~p"/balances",
      ~p"/balances/#{context.leave_type}",
      ~p"/people/#{who}",
      ~p"/people/#{who}/balances",
      ~p"/people/#{who}/balances/#{context.leave_type}"
    ]
  end

  # The pages the administrator's live session holds, all of them.
  defp the_administrators(context) do
    [
      ~p"/people",
      ~p"/people/new",
      ~p"/people/#{context.admin}/edit",
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
    paths =
      theirs(context, context.admin) ++
        the_administrators(context) ++ [~p"/people/#{context.other}"]

    Enum.each(paths, fn path ->
      assert {:ok, _live, html} = live(context.conn, path)
      assert html =~ "Fernbank Collective" or html =~ "<h1>"
    end)
  end

  test "a page is served with a policy naming the only hosts it loads from", context do
    assert ["default-src 'self'" <> _rest = policy] =
             context.conn |> get(~p"/") |> get_resp_header("content-security-policy")

    assert policy =~ "style-src 'self' https://fonts.googleapis.com"
    assert policy =~ "font-src https://fonts.gstatic.com"
  end

  test "every page that is a member's own renders for them", context do
    conn = sign_in(build_conn(), context.other)

    Enum.each(theirs(context, context.other), fn path ->
      assert {:ok, _live, html} = live(conn, path)
      assert html =~ "<h1>"
    end)
  end

  test "a member is turned away from every page in the administrator's live session", context do
    conn = sign_in(build_conn(), context.other)

    Enum.each(the_administrators(context), fn path ->
      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, path)
      assert flash == %{"error" => "That page is the administrator's."}
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
    assert html =~ "Monday 7 – Friday 11 October"

    {:ok, _live, html} = live(context.conn, ~p"/away?month=2030-10")
    assert html =~ ~s(data-leave="pending")
  end
end
