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

  test "a live mount whose session names nobody is sent to sign in" do
    assert {:halt, socket} = SignIn.on_mount(:current_person, %{}, %{}, %Socket{})
    assert {:redirect, %{to: "/sign-in"}} = socket.redirected
  end

  test "whoever the session names is who an error report names", %{conn: conn} do
    person = Fixtures.person(%{organisation_id: Fixtures.organisation().id})

    SignIn.fetch_current_person(sign_in(conn, person), [])

    assert Sentry.Context.get_all().user == %{id: person.id, email: person.email}
  end
end
