defmodule LeafWeb.SignInTest do
  @moduledoc """
  Signing in, called directly where the router cannot show it.

  A stranger cannot reach the live mount through the router — `require_person/2` turns them away at
  the dead render first — so the hook is called directly, which is the only way to see it refuse.
  """

  use LeafWeb.ConnCase, async: true

  alias Leaf.Fixtures
  alias LeafWeb.SignIn
  alias Phoenix.LiveView.Socket

  test "a session naming nobody, or whose impersonation has run out, is sent to sign in", %{
    conn: conn
  } do
    assert {:halt, socket} = SignIn.on_mount(:current_person, %{}, %{}, %Socket{})
    assert {:redirect, %{to: "/sign-in"}} = socket.redirected

    organisation = Fixtures.organisation()
    admin = Fixtures.person(%{organisation_id: organisation.id, role: :admin})
    person = Fixtures.person(%{organisation_id: organisation.id})
    session = %{"person_id" => person.id, "impersonation" => {admin.id, 0}}

    assert {:halt, socket} = SignIn.on_mount(:current_person, %{}, session, %Socket{})
    assert {:redirect, %{to: "/sign-in"}} = socket.redirected

    assert conn |> Plug.Test.init_test_session(session) |> get(~p"/") |> redirected_to() ==
             "/sign-in"
  end

  test "whoever the session names is who an error report names", %{conn: conn} do
    person = Fixtures.person(%{organisation_id: Fixtures.organisation().id})

    SignIn.fetch_current_person(sign_in(conn, person), [])

    assert Sentry.Context.get_all().user == %{id: person.id, email: person.email}
  end
end
