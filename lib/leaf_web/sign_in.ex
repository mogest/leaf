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
  alias LeafWeb.Viewer
  alias Phoenix.Component
  alias Phoenix.LiveView

  @named "person_id"

  @doc "Puts whoever the session names on the connection."
  @spec fetch_current_person(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_person(conn, _opts) do
    assign(conn, :current_person, named(get_session(conn, @named)))
  end

  @doc """
  Puts whoever the session names on the socket, and turns anybody else away from an admin page.

  `:current_person` assigns the person twice over: as themselves, which is the actor every context
  write takes, and as a `Viewer`, which is all the chrome around a page is given.

  `:admin` runs after `:current_person`, so the pages only an administrator may open say so in the
  router rather than each checking for themselves.
  """
  @spec on_mount(atom(), map(), map(), LiveView.Socket.t()) ::
          {:cont, LiveView.Socket.t()} | {:halt, LiveView.Socket.t()}
  def on_mount(:current_person, _params, session, socket) do
    {:cont, viewing(socket, named(session[@named]))}
  end

  def on_mount(:admin, _params, _session, %{assigns: %{current_person: %{role: :admin}}} = socket) do
    {:cont, socket}
  end

  def on_mount(:admin, _params, _session, socket) do
    {:halt, socket |> LiveView.put_flash(:error, refused()) |> LiveView.redirect(to: "/")}
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

  defp refused, do: "That page is the administrator's."

  defp viewing(socket, person) do
    socket
    |> Component.assign(:current_person, person)
    |> Component.assign(:viewer, viewer(person))
  end

  defp viewer(nil), do: nil
  defp viewer(person), do: Viewer.new(person)

  defp named(nil), do: nil

  defp named(id) do
    case People.fetch_person(id) do
      {:ok, person} -> person
      :error -> nil
    end
  end
end
