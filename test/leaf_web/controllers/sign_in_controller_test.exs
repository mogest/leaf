defmodule LeafWeb.SignInControllerTest do
  use LeafWeb.ConnCase, async: true
  use Mimic

  @moduletag :capture_log

  alias Assent.Strategy.Google
  alias Leaf.Fixtures
  alias Leaf.People

  setup do
    person = Fixtures.person(%{organisation_id: Fixtures.organisation().id})

    stub(Google, :authorize_url, fn config ->
      assert config[:redirect_uri] == url(~p"/sign-in/callback")
      {:ok, %{url: "https://accounts.google.com/o/oauth2/auth", session_params: %{state: "s1"}}}
    end)

    {:ok, conn: get(build_conn(), ~p"/sign-in/start"), person: person}
  end

  test "somebody the provider vouches for is signed in as the person with their address",
       context do
    assert redirected_to(context.conn) == "https://accounts.google.com/o/oauth2/auth"

    expect(Google, :callback, fn config, %{"code" => "c1", "state" => "s1"} ->
      assert config[:session_params] == %{state: "s1"}
      {:ok, %{user: %{"email" => String.upcase(context.person.email), "email_verified" => true}}}
    end)

    conn = get(recycle(context.conn), ~p"/sign-in/callback", %{"code" => "c1", "state" => "s1"})

    assert redirected_to(conn) == "/"
    assert get_session(conn, "person_id") == context.person.id
  end

  test "an address nobody in Leaf has, or only somebody archived, is turned away", context do
    {:ok, person} =
      People.update_person(context.person, nil, %{employment_end_date: ~D[2026-01-30]})

    {:ok, archived} = People.archive_person(person, nil)

    for email <- ["stranger@example.test", archived.email] do
      expect(Google, :callback, fn _config, _params ->
        {:ok, %{user: %{"email" => email, "email_verified" => true}}}
      end)

      conn = get(recycle(context.conn), ~p"/sign-in/callback")

      assert redirected_to(conn) == "/sign-in"
      assert conn.assigns.flash["error"] == "Nobody in Leaf has the address #{email}."
      refute get_session(conn, "person_id")
    end
  end

  test "somebody outside their employment dates is turned away without a session", context do
    {:ok, leaver} =
      People.update_person(context.person, nil, %{
        employment_end_date: Date.add(Date.utc_today(), -1)
      })

    expect(Google, :callback, fn _config, _params ->
      {:ok, %{user: %{"email" => leaver.email, "email_verified" => true}}}
    end)

    conn = get(recycle(context.conn), ~p"/sign-in/callback")

    assert redirected_to(conn) == "/sign-in"
    assert conn.assigns.flash["error"] == "Leaf is only open to you while you're employed."
    refute get_session(conn, "person_id")
  end

  test "an unverified address or a failed callback is turned away", context do
    expect(Google, :callback, fn _config, _params ->
      {:ok, %{user: %{"email" => context.person.email, "email_verified" => false}}}
    end)

    conn = get(recycle(context.conn), ~p"/sign-in/callback")

    assert redirected_to(conn) == "/sign-in"
    assert conn.assigns.flash["error"] == "Signing in didn't work. Try again."
    refute get_session(conn, "person_id")

    expect(Google, :callback, fn _config, _params ->
      {:error, %Assent.CallbackError{message: "denied"}}
    end)

    conn = get(recycle(get(build_conn(), ~p"/sign-in/start")), ~p"/sign-in/callback")

    assert conn.assigns.flash["error"] == "Signing in didn't work. Try again."
  end

  test "a callback no sign-in started is turned away without asking the provider" do
    reject(&Google.callback/2)

    conn = get(build_conn(), ~p"/sign-in/callback", %{"code" => "c1", "state" => "s1"})

    assert redirected_to(conn) == "/sign-in"
    refute get_session(conn, "person_id")
  end
end
