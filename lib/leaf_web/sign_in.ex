defmodule LeafWeb.SignIn do
  @moduledoc """
  Who the session names, and turning away anybody it does not.

  Who that is gets settled by `LeafWeb.SignInController`, in development by
  `LeafWeb.SignInPickerController`, or by an administrator impersonating them through
  `LeafWeb.ImpersonationController`; from then on the session holds only their id, when it was
  signed in, and while impersonating, the administrator's id. A session lasts a week from signing in
  and an impersonation an hour, after which the session names nobody. Neither is renewed by use, so
  a copied cookie runs out with the rest.

  Nor does it name anybody outside their employment dates but an administrator, or somebody an
  administrator is impersonating: they are sent to sign in and told why, and an open page stops at
  their next event. Somebody archived it does not name at all.

  Each signing in names a socket id of its own, and signing in again or out disconnects whatever the
  last one had open, so no page goes on acting as somebody the session no longer names.
  """

  import Phoenix.Controller
  import Plug.Conn

  alias Leaf.People
  alias LeafWeb.AuthorizedEvents
  alias LeafWeb.Viewer
  alias Phoenix.Component
  alias Phoenix.LiveView

  @named "person_id"
  @signed_in_at "signed_in_at"
  @impersonation "impersonation"
  @socket "live_socket_id"
  @impersonation_lasts 60 * 60
  @session_lasts 7 * 24 * 60 * 60

  @doc "Puts whoever the session names on the connection."
  @spec fetch_current_person(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_person(conn, _opts) do
    case signed_in(get_session(conn)) do
      :outside -> conn |> put_private(:outside, true) |> assign(:current_person, nil)
      person -> assign(conn, :current_person, person)
    end
  end

  @doc """
  Puts whoever the session names on the socket, and turns anybody else away.

  `:current_person` assigns the person twice over: as themselves, which is the actor every context
  write takes even while impersonated, and as a `Viewer`, which is all the chrome around a page is
  given. `:zone` is their time zone, which every stored instant is shown in. Each event reads
  `:current_person` afresh, so a role changed since mount counts on a page already open, and then
  goes through `LeafWeb.AuthorizedEvents`, since a page a member may open can still carry an
  administrator's buttons. The `Viewer` keeps what mount saw. A page sends itself to sign in when
  the session or its impersonation runs out, rather than waiting for the next mount to find it over.

  A session naming nobody is sent to sign in, the same as `require_person/2` sends the dead render.
  The requirement is not a hook of its own: every live session needs `:current_person`, so a page
  cannot be mounted by a stranger through having forgotten one.

  `:admin` runs after `:current_person`, on each page only an administrator may open.
  """
  @spec on_mount(atom(), map(), map(), LiveView.Socket.t()) ::
          {:cont, LiveView.Socket.t()} | {:halt, LiveView.Socket.t()}
  def on_mount(:current_person, _params, session, socket) do
    case signed_in(session) do
      nil -> {:halt, LiveView.redirect(socket, to: "/sign-in")}
      :outside -> {:halt, turned_away(socket)}
      person -> {:cont, viewing(socket, person, session)}
    end
  end

  def on_mount(:admin, _params, _session, %{assigns: %{current_person: %{role: :admin}}} = socket) do
    {:cont, socket}
  end

  def on_mount(:admin, _params, _session, socket) do
    {:halt, socket |> LiveView.put_flash(:error, refused()) |> LiveView.redirect(to: "/")}
  end

  @doc "Names `person` for a week, ending any impersonation and disconnecting open pages."
  @spec sign_in(Plug.Conn.t(), People.Person.t()) :: Plug.Conn.t()
  def sign_in(conn, person) do
    conn |> name(person.id) |> put_session(@signed_in_at, System.os_time(:second))
  end

  @doc "Names `person` for an hour, or until the session runs out, remembering who started it."
  @spec impersonate(Plug.Conn.t(), People.Person.t()) :: Plug.Conn.t()
  def impersonate(conn, person) do
    impersonation =
      get_session(conn, @impersonation) ||
        {conn.assigns.current_person.id, System.os_time(:second) + @impersonation_lasts}

    conn |> name(person.id) |> put_session(@impersonation, impersonation)
  end

  @doc "Names whoever was impersonating in the session again."
  @spec stop_impersonating(Plug.Conn.t()) :: Plug.Conn.t()
  def stop_impersonating(conn) do
    case get_session(conn, @impersonation) do
      nil -> conn
      {impersonator, _until} -> name(conn, impersonator)
    end
  end

  @doc "Forgets whoever the session named."
  @spec sign_out(Plug.Conn.t()) :: Plug.Conn.t()
  def sign_out(conn), do: conn |> disconnect() |> configure_session(drop: true)

  @doc "Sends anyone the session does not name to sign in."
  @spec require_person(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_person(%{assigns: %{current_person: nil}, private: %{outside: true}} = conn, _opts) do
    conn |> put_flash(:error, outside()) |> redirect(to: "/sign-in") |> halt()
  end

  def require_person(%{assigns: %{current_person: nil}} = conn, _opts) do
    conn |> redirect(to: "/sign-in") |> halt()
  end

  def require_person(conn, _opts), do: conn

  @doc "Turns away anybody but an administrator, as `on_mount(:admin, …)` does a page."
  @spec require_admin(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_admin(%{assigns: %{current_person: %{role: :admin}}} = conn, _opts), do: conn

  def require_admin(conn, _opts) do
    conn |> put_flash(:error, refused()) |> redirect(to: "/") |> halt()
  end

  @doc "Why somebody outside their employment dates is turned away."
  @spec outside() :: String.t()
  def outside, do: "You can only use Leaf during your employment."

  defp refused, do: "Only administrators can open that page."

  defp turned_away(socket) do
    socket |> LiveView.put_flash(:error, outside()) |> LiveView.redirect(to: "/sign-in")
  end

  defp name(conn, id) do
    conn
    |> disconnect()
    |> configure_session(renew: true)
    |> delete_session(@impersonation)
    |> put_session(@named, id)
    |> put_session(@socket, "session:#{Ecto.UUID.generate()}")
  end

  defp disconnect(conn) do
    case get_session(conn, @socket) do
      nil -> :ok
      socket -> LeafWeb.Endpoint.broadcast!(socket, "disconnect", %{})
    end

    conn
  end

  defp signed_in(%{@named => id, @signed_in_at => signed_in_at} = session) do
    case System.os_time(:second) < ends(signed_in_at, session[@impersonation]) do
      true -> id |> named() |> admitted(session[@impersonation] != nil)
      false -> nil
    end
  end

  defp signed_in(_session), do: nil

  defp ends(signed_in_at, nil), do: signed_in_at + @session_lasts
  defp ends(signed_in_at, {_impersonator, until}), do: min(signed_in_at + @session_lasts, until)

  defp viewing(socket, person, session) do
    socket
    |> Component.assign(:current_person, person)
    |> Component.assign(:viewer, Viewer.new(person, session[@impersonation] != nil))
    |> Component.assign(:zone, People.time_zone(person))
    |> LiveView.attach_hook(:current_person, :handle_event, &current/3)
    |> AuthorizedEvents.enforce()
    |> expiring(
      ends(session[@signed_in_at], session[@impersonation]),
      LiveView.connected?(socket)
    )
  end

  defp current(_event, _params, socket) do
    case People.fetch_unarchived_person(socket.assigns.current_person.id) do
      {:ok, person} -> carry_on(socket, admitted(person, socket.assigns.viewer.impersonated?))
      :error -> {:halt, LiveView.redirect(socket, to: "/sign-in")}
    end
  end

  defp carry_on(socket, :outside), do: {:halt, turned_away(socket)}
  defp carry_on(socket, person), do: {:cont, Component.assign(socket, :current_person, person)}

  defp admitted(nil, _impersonated?), do: nil
  defp admitted(person, true), do: person

  defp admitted(person, false) do
    case People.admitted?(person) do
      true -> person
      false -> :outside
    end
  end

  defp expiring(socket, ends, true) do
    Process.send_after(self(), :session_over, max(ends - System.os_time(:second), 0) * 1000)

    LiveView.attach_hook(socket, :session_over, :handle_info, &over/2)
  end

  defp expiring(socket, _ends, false), do: socket

  defp over(:session_over, socket), do: {:halt, LiveView.redirect(socket, to: "/sign-in")}
  defp over(_message, socket), do: {:cont, socket}

  defp named(id) do
    case People.fetch_unarchived_person(id) do
      {:ok, person} ->
        Sentry.Context.set_user_context(%{id: person.id, email: person.email})
        person

      :error ->
        nil
    end
  end
end
