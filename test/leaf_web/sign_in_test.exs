defmodule LeafWeb.SignInTest do
  @moduledoc """
  The live mount's half of requiring somebody to be signed in.

  A stranger cannot reach it through the router — `require_person/2` turns them away at the dead
  render first — so the hook is called directly, which is the only way to see it refuse.
  """

  use ExUnit.Case, async: true

  alias LeafWeb.SignIn
  alias Phoenix.LiveView.Socket

  test "a live mount whose session names nobody is sent to sign in" do
    assert {:halt, socket} = SignIn.on_mount(:current_person, %{}, %{}, %Socket{})
    assert {:redirect, %{to: "/sign-in"}} = socket.redirected
  end
end
