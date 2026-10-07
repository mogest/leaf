defmodule LeafWeb.CalendarFormLive do
  @moduledoc "Correcting a calendar's name, country and time zone."

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Changeset
  alias Leaf.Org

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    case Org.fetch_calendar(id) do
      {:ok, calendar} -> {:ok, opened(socket, calendar)}
      :error -> {:ok, unknown(socket)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"calendar" => params}, socket) do
    changeset = Changeset.change(socket.assigns.calendar, params)

    country_code =
      params["country_code"] || (socket.assigns.country || socket.assigns.calendar).country_code

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign(:time_zones, Org.time_zones(country_code))}
  end

  @role :admin
  def handle_event("save", %{"calendar" => params}, socket) do
    written = Org.update_calendar(socket.assigns.calendar, socket.assigns.current_person, params)

    {:noreply, saved(socket, written)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <nav aria-label="Breadcrumb">
          <.link navigate={~p"/settings/calendars"}>Calendars</.link>
          <.link :if={@country} navigate={~p"/settings/calendars/#{@country}"}>{@country.name}</.link>
          <.link navigate={~p"/settings/calendars/#{@calendar}"}>{@calendar.name}</.link>
        </nav>
        <h1>Edit the calendar</h1>
      </header>

      <.form id="calendar" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input
            :if={!@country}
            field={@form[:country_code]}
            type="text"
            label="Country code, two letters"
          />
          <.input
            field={@form[:time_zone]}
            type="select"
            label="Time zone"
            prompt="Choose one"
            options={@time_zones}
          />
        </section>

        <footer>
          <p :if={@calendar.regions != []}>
            Changing the time zone here leaves its regions' zones as they are.
          </p>
          <button class="button" type="submit">Save</button>
          <.link navigate={~p"/settings/calendars/#{@calendar}"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp opened(socket, calendar) do
    socket
    |> assign(:page_title, "Edit #{calendar.name}")
    |> assign(:calendar, calendar)
    |> assign(:country, calendar.parent)
    |> assign(:form, to_form(Changeset.change(calendar, %{})))
    |> assign(:time_zones, Org.time_zones((calendar.parent || calendar).country_code))
  end

  defp unknown(socket) do
    socket
    |> put_flash(:error, "That calendar is not on record.")
    |> push_navigate(to: ~p"/settings/calendars")
  end

  defp saved(socket, {:ok, calendar}) do
    socket |> put_flash(:info, "Saved.") |> push_navigate(to: ~p"/settings/calendars/#{calendar}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
