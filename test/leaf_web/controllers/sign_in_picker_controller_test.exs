defmodule LeafWeb.SignInPickerControllerTest do
  # Not async: switching the picker off is global config.
  use LeafWeb.ConnCase, async: false

  alias Leaf.Fixtures

  test "picking somebody signs in as them, and is not found once switched off", %{conn: conn} do
    person = Fixtures.person(%{organisation_id: Fixtures.organisation().id})

    conn = post(conn, ~p"/sign-in/pick/#{person.id}")

    assert redirected_to(conn) == "/"
    assert get_session(conn, "person_id") == person.id

    Application.put_env(:leaf, LeafWeb.SignInPickerController, enabled: false)
    on_exit(fn -> Application.put_env(:leaf, LeafWeb.SignInPickerController, enabled: true) end)

    assert build_conn() |> get(~p"/sign-in/pick") |> response(404)
    assert build_conn() |> post(~p"/sign-in/pick/#{person.id}") |> response(404)
    refute build_conn() |> get(~p"/sign-in") |> html_response(200) =~ "/sign-in/pick"
  end
end
