defmodule LeafWeb.SignInTest do
  @moduledoc """
  Signing in, called directly where the router cannot show it.

  A stranger cannot reach the live mount through the router — `require_person/2` turns them away at
  the dead render first — so the hook is called directly, which is the only way to see it refuse.
  """

  use LeafWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Leaf.People
  alias LeafWeb.SignIn
  alias Phoenix.LiveView.Socket

  test "a session naming nobody or somebody archived, too old, or whose impersonation has run out, is sent to sign in",
       %{conn: conn} do
    organisation = Fixtures.organisation()
    admin = Fixtures.person(%{organisation_id: organisation.id, role: :admin})
    person = Fixtures.person(%{organisation_id: organisation.id})

    leaver =
      Fixtures.person(%{organisation_id: organisation.id, employment_end_date: ~D[2026-01-30]})

    archived =
      Fixtures.person(%{
        organisation_id: organisation.id,
        role: :admin,
        employment_end_date: ~D[2026-01-30]
      })

    {:ok, _archived} = People.archive_person(archived, nil)
    now = System.os_time(:second)

    for session <- [
          %{},
          %{"person_id" => leaver.id},
          %{"person_id" => leaver.id, "signed_in_at" => now - 8 * 24 * 60 * 60},
          %{"person_id" => person.id, "signed_in_at" => now, "impersonation" => {admin.id, 0}},
          %{"person_id" => archived.id, "signed_in_at" => now},
          %{
            "person_id" => archived.id,
            "signed_in_at" => now,
            "impersonation" => {admin.id, now + 3600}
          },
          %{
            "person_id" => person.id,
            "signed_in_at" => now - 8 * 24 * 60 * 60,
            "impersonation" => {admin.id, now + 3600}
          }
        ] do
      assert {:halt, socket} = SignIn.on_mount(:current_person, %{}, session, %Socket{})
      assert {:redirect, %{to: "/sign-in"}} = socket.redirected

      assert conn |> Plug.Test.init_test_session(session) |> get(~p"/") |> redirected_to() ==
               "/sign-in"
    end
  end

  test "somebody outside their employment dates is turned away saying why, unless an administrator or impersonated",
       %{conn: conn} do
    organisation = Fixtures.organisation()
    yesterday = Date.add(Date.utc_today(), -1)
    leaver = Fixtures.person(%{organisation_id: organisation.id, employment_end_date: yesterday})

    starter =
      Fixtures.person(%{
        organisation_id: organisation.id,
        employment_start_date: Date.add(Date.utc_today(), 2)
      })

    admin =
      Fixtures.person(%{
        organisation_id: organisation.id,
        role: :admin,
        employment_end_date: yesterday
      })

    now = System.os_time(:second)

    for person <- [leaver, starter] do
      session = %{"person_id" => person.id, "signed_in_at" => now}
      mounting = %Socket{assigns: %{__changed__: %{}, flash: %{}}}

      assert {:halt, socket} = SignIn.on_mount(:current_person, %{}, session, mounting)
      assert {:redirect, %{to: "/sign-in"}} = socket.redirected
      assert socket.assigns.flash["error"] == "You can only use Leaf during your employment."

      signed_in = Plug.Test.init_test_session(conn, session)
      turned_away = get(signed_in, ~p"/")
      assert redirected_to(turned_away) == "/sign-in"

      assert turned_away.assigns.flash["error"] ==
               "You can only use Leaf during your employment."

      refute get(signed_in, ~p"/sign-in").assigns.flash["error"]
    end

    for session <- [
          %{"person_id" => admin.id, "signed_in_at" => now},
          %{
            "person_id" => leaver.id,
            "signed_in_at" => now,
            "impersonation" => {admin.id, now + 3600}
          }
        ] do
      assert conn |> Plug.Test.init_test_session(session) |> get(~p"/") |> html_response(200)
    end
  end

  test "an open page stops acting for somebody once their employment has ended", %{conn: conn} do
    person = Fixtures.person(%{organisation_id: Fixtures.organisation().id})
    {:ok, live, _html} = live(sign_in(conn, person), ~p"/")

    {:ok, _left} =
      People.update_person(person, nil, %{employment_end_date: Date.add(Date.utc_today(), -1)})

    assert {:error, {:redirect, %{to: "/sign-in"}}} = render_hook(live, "anything", %{})
  end

  test "a session signed in under a week ago is let in", %{conn: conn} do
    person = Fixtures.person(%{organisation_id: Fixtures.organisation().id})

    session = %{
      "person_id" => person.id,
      "signed_in_at" => System.os_time(:second) - 6 * 24 * 60 * 60
    }

    assert conn |> Plug.Test.init_test_session(session) |> get(~p"/") |> html_response(200)
  end

  test "whoever the session names is who an error report names", %{conn: conn} do
    person = Fixtures.person(%{organisation_id: Fixtures.organisation().id})

    SignIn.fetch_current_person(sign_in(conn, person), [])

    assert Sentry.Context.get_all().user == %{id: person.id, email: person.email}
  end
end
