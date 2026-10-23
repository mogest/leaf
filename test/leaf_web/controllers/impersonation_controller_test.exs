defmodule LeafWeb.ImpersonationControllerTest do
  # Not async: switching impersonation off is global config.
  use LeafWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Leaf.Fixtures
  alias Phoenix.Socket.Broadcast

  setup %{conn: conn} do
    organisation = Fixtures.organisation()
    admin = Fixtures.person(%{organisation_id: organisation.id, name: "Kit Rua", role: :admin})
    person = Fixtures.person(%{organisation_id: organisation.id, name: "Rae Halloran"})

    %{conn: sign_in(conn, admin), admin: admin, person: person}
  end

  test "an administrator impersonates somebody for an hour, acting as them until they stop",
       context do
    {:ok, live, _html} = live(context.conn, ~p"/people/#{context.person}")
    assert has_element?(live, "button", "Impersonate")

    conn = put_session(context.conn, "live_socket_id", "session:before")
    LeafWeb.Endpoint.subscribe("session:before")

    conn = post(conn, ~p"/impersonate/#{context.person}")

    assert redirected_to(conn) == "/"
    assert get_session(conn, "person_id") == context.person.id
    assert {admin_id, until} = get_session(conn, "impersonation")
    assert admin_id == context.admin.id
    assert_in_delta until, System.os_time(:second) + 60 * 60, 5
    assert_receive %Broadcast{topic: "session:before", event: "disconnect"}

    {:ok, live, _html} = live(recycle(conn), ~p"/")
    assert has_element?(live, "aside", "Impersonating Rae Halloran.")
    send(live.pid, :session_over)
    assert_redirect(live, "/sign-in")

    impersonating = get_session(conn, "live_socket_id")
    refute impersonating == "session:before"
    LeafWeb.Endpoint.subscribe(impersonating)

    conn = delete(recycle(conn), ~p"/impersonate")

    assert redirected_to(conn) == "/people/#{context.person.id}"
    assert get_session(conn, "person_id") == context.admin.id
    refute get_session(conn, "impersonation")
    assert_receive %Broadcast{topic: ^impersonating, event: "disconnect"}

    stopped = get_session(conn, "live_socket_id")
    refute stopped == impersonating
    LeafWeb.Endpoint.subscribe(stopped)

    conn = delete(recycle(conn), ~p"/sign-out")

    assert conn |> recycle() |> get(~p"/") |> redirected_to() == "/sign-in"
    assert_receive %Broadcast{topic: ^stopped, event: "disconnect"}
  end

  test "impersonating from an impersonated administrator keeps who started it", context do
    other = Fixtures.person(%{organisation_id: context.person.organisation_id, role: :admin})

    conn = post(context.conn, ~p"/impersonate/#{other}")
    started = get_session(conn, "impersonation")
    conn = post(recycle(conn), ~p"/impersonate/#{context.person}")

    assert get_session(conn, "person_id") == context.person.id
    assert get_session(conn, "impersonation") == started
  end

  test "only an administrator impersonates, never themselves, and nobody starts once switched off",
       context do
    conn = post(context.conn, ~p"/impersonate/#{context.admin}")

    assert redirected_to(conn) == "/people/#{context.admin.id}"
    refute get_session(conn, "impersonation")

    conn = context.conn |> sign_in(context.person) |> post(~p"/impersonate/#{context.admin}")

    assert redirected_to(conn) == "/"
    assert get_session(conn, "person_id") == context.person.id

    Application.put_env(:leaf, LeafWeb.ImpersonationController, enabled: false)
    on_exit(fn -> Application.put_env(:leaf, LeafWeb.ImpersonationController, enabled: true) end)

    {:ok, live, _html} = live(context.conn, ~p"/people/#{context.person}")
    refute has_element?(live, "button", "Impersonate")
    assert context.conn |> post(~p"/impersonate/#{context.person}") |> response(404)

    impersonation = {context.admin.id, System.os_time(:second) + 60}

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{
        "person_id" => context.person.id,
        "signed_in_at" => System.os_time(:second),
        "impersonation" => impersonation
      })
      |> delete(~p"/impersonate")

    assert redirected_to(conn) == "/people/#{context.person.id}"
    assert get_session(conn, "person_id") == context.admin.id
  end
end
