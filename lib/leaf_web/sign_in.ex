defmodule LeafWeb.SignIn do
  @moduledoc """
  Signing in, until there is real authentication.

  Picking a name off a list is the whole of it: no password, nothing verified, nothing stopping
  anybody from being anybody. It exists so every page downstream can be written against a
  `current_person` and need no changing when Google OAuth (SCOPE.md §5.9) arrives. That lands last
  on purpose, so the pages people actually use get built first.
  """

  import Phoenix.Controller
  import Plug.Conn

  alias Leaf.People
  alias Phoenix.Component
  alias Phoenix.LiveView

  @named "person_id"

  @doc "Puts whoever the session names on the connection."
  @spec fetch_current_person(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_person(conn, _opts) do
    assign(conn, :current_person, named(get_session(conn, @named)))
  end

  @doc "Puts whoever the session names on the socket."
  @spec on_mount(atom(), map(), map(), LiveView.Socket.t()) :: {:cont, LiveView.Socket.t()}
  def on_mount(:current_person, _params, session, socket) do
    {:cont, Component.assign(socket, :current_person, named(session[@named]))}
  end

  @doc "Names `person` in the session, on a fresh one so nothing carries over."
  @spec sign_in(Plug.Conn.t(), People.Person.t()) :: Plug.Conn.t()
  def sign_in(conn, person) do
    conn |> configure_session(renew: true) |> put_session(@named, person.id)
  end

  @doc "Forgets whoever the session named."
  @spec sign_out(Plug.Conn.t()) :: Plug.Conn.t()
  def sign_out(conn), do: configure_session(conn, drop: true)

  @doc "Sends anyone the session does not name to the list of people."
  @spec require_person(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_person(%{assigns: %{current_person: nil}} = conn, _opts) do
    conn |> redirect(to: "/sign-in") |> halt()
  end

  def require_person(conn, _opts), do: conn

  defp named(nil), do: nil

  defp named(id) do
    case People.fetch_person(id) do
      {:ok, person} -> person
      :error -> nil
    end
  end
end
