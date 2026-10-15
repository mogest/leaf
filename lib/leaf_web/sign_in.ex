defmodule LeafWeb.SignIn do
  @moduledoc """
  Who the session names, and turning away anybody it does not.

  Who that is gets settled by `LeafWeb.SignInController`, in development by
  `LeafWeb.SignInPickerController`, or by an administrator impersonating them through
  `LeafWeb.ImpersonationController`; from then on the session holds only their id, and while
  impersonating, the administrator's. An impersonation lasts an hour, after which the session names
  nobody.

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
  @impersonation "impersonation"
  @socket "live_socket_id"
  @impersonation_lasts 60 * 60

  @doc "Puts whoever the session names on the connection."
  @spec fetch_current_person(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_person(conn, _opts) do
    assign(conn, :current_person, signed_in(get_session(conn)))
  end

  @doc """
  Puts whoever the session names on the socket, and turns anybody else away.

  `:current_person` assigns the person twice over: as themselves, which is the actor every context
  write takes even while impersonated, and as a `Viewer`, which is all the chrome around a page is
  given. `:zone` is their time zone, which every stored instant is shown in. It also puts
  `LeafWeb.AuthorizedEvents` in front of every event, since a page a member may open can still
  carry an administrator's buttons. An impersonated page sends itself to sign in when the hour is
  up, rather than waiting for the next mount to find it over.

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
      person -> {:cont, viewing(socket, person, session[@impersonation])}
    end
  end

  def on_mount(:admin, _params, _session, %{assigns: %{current_person: %{role: :admin}}} = socket) do
    {:cont, socket}
  end

  def on_mount(:admin, _params, _session, socket) do
    {:halt, socket |> LiveView.put_flash(:error, refused()) |> LiveView.redirect(to: "/")}
  end

  @doc "Names `person` in the session, ending any impersonation and disconnecting open pages."
  @spec sign_in(Plug.Conn.t(), People.Person.t()) :: Plug.Conn.t()
  def sign_in(conn, person), do: name(conn, person.id)

  @doc "Names `person` until the impersonation's hour is up, remembering who started it."
  @spec impersonate(Plug.Conn.t(), People.Person.t()) :: Plug.Conn.t()
  def impersonate(conn, person) do
    impersonation =
      get_session(conn, @impersonation) ||
        {conn.assigns.current_person.id, System.os_time(:second) + @impersonation_lasts}

    conn |> sign_in(person) |> put_session(@impersonation, impersonation)
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

  defp refused, do: "That page is the administrator's."

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

  defp signed_in(%{@named => id, @impersonation => {_impersonator, until}}) do
    case System.os_time(:second) < until do
      true -> named(id)
      false -> nil
    end
  end

  defp signed_in(%{@named => id}), do: named(id)
  defp signed_in(_session), do: nil

  defp viewing(socket, person, impersonation) do
    socket
    |> Component.assign(:current_person, person)
    |> Component.assign(:viewer, Viewer.new(person, impersonation != nil))
    |> Component.assign(:zone, People.time_zone(person))
    |> AuthorizedEvents.enforce()
    |> expiring(impersonation, LiveView.connected?(socket))
  end

  defp expiring(socket, {_impersonator, until}, true) do
    Process.send_after(
      self(),
      :impersonation_over,
      max(until - System.os_time(:second), 0) * 1000
    )

    LiveView.attach_hook(socket, :impersonation_over, :handle_info, &over/2)
  end

  defp expiring(socket, _impersonation, _connected?), do: socket

  defp over(:impersonation_over, socket), do: {:halt, LiveView.redirect(socket, to: "/sign-in")}
  defp over(_message, socket), do: {:cont, socket}

  defp named(id) do
    case People.fetch_person(id) do
      {:ok, person} ->
        Sentry.Context.set_user_context(%{id: person.id, email: person.email})
        person

      :error ->
        nil
    end
  end
end
