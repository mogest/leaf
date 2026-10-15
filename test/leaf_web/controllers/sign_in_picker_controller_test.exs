defmodule LeafWeb.SignInPickerControllerTest do
  # Not async: switching the picker off is global config.
  use LeafWeb.ConnCase, async: false

  alias Leaf.Fixtures
  alias Phoenix.Socket.Broadcast

  setup do
    %{person: Fixtures.person(%{organisation_id: Fixtures.organisation().id})}
  end

  test "picking somebody signs in as them, disconnecting the last session's pages", context do
    LeafWeb.Endpoint.subscribe("session:before")

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"live_socket_id" => "session:before"})
      |> post(~p"/sign-in/pick/#{context.person.id}")

    assert redirected_to(conn) == "/"
    assert get_session(conn, "person_id") == context.person.id
    assert_receive %Broadcast{topic: "session:before", event: "disconnect"}
    refute get_session(conn, "live_socket_id") == "session:before"
  end

  test "picking is not found outside development", context do
    Application.put_env(:leaf, :dev_routes, false)
    on_exit(fn -> Application.put_env(:leaf, :dev_routes, true) end)

    assert build_conn() |> get(~p"/sign-in/pick") |> response(404)
    assert build_conn() |> post(~p"/sign-in/pick/#{context.person.id}") |> response(404)
    refute build_conn() |> get(~p"/sign-in") |> html_response(200) =~ "/sign-in/pick"
  end
end
