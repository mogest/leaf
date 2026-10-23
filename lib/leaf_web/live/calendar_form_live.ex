defmodule LeafWeb.CalendarFormLive do
  @moduledoc "Adding a country's calendar, and correcting a calendar's name, country and time zone."

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Changeset
  alias Leaf.Org

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case amending(socket.assigns.live_action, params) do
      {:ok, calendar} -> {:ok, opened(socket, calendar)}
      :error -> {:ok, unknown(socket)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"calendar" => params}, socket) do
    changeset = change(socket.assigns.calendar, socket.assigns.organisation, params)
    time_zones = Org.time_zones(params["country_code"] || country_code(socket.assigns.calendar))

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign(:time_zones, time_zones)}
  end

  @role :admin
  def handle_event("save", %{"calendar" => params}, socket) do
    {:noreply, saved(socket, write(socket.assigns, params))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <nav aria-label="Breadcrumb">
          <.link navigate={~p"/settings/calendars"}>Calendars</.link>
          <.link :if={@country} navigate={~p"/settings/calendars/#{@country}"}>{@country.name}</.link>
          <.link :if={@calendar} navigate={~p"/settings/calendars/#{@calendar}"}>{@calendar.name}</.link>
        </nav>
        <h1>{@page_title}</h1>
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
          <p :if={@calendar && @calendar.regions != []}>
            Changing this time zone doesn't change its regions' time zones.
          </p>
          <button class="button" type="submit">Save</button>
          <.link navigate={back(@calendar)}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp amending(:new, _params), do: {:ok, nil}
  defp amending(:edit, %{"id" => id}), do: Org.fetch_calendar(id)

  defp opened(socket, calendar) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)

    socket
    |> assign(:page_title, title(calendar))
    |> assign(:calendar, calendar)
    |> assign(:country, calendar && calendar.parent)
    |> assign(:organisation, organisation)
    |> assign(:form, to_form(change(calendar, organisation, %{})))
    |> assign(:time_zones, Org.time_zones(country_code(calendar)))
  end

  defp unknown(socket) do
    socket
    |> put_flash(:error, "Calendar not found.")
    |> push_navigate(to: ~p"/settings/calendars")
  end

  defp title(nil), do: "Add a country"
  defp title(calendar), do: "Edit #{calendar.name}"

  defp back(nil), do: ~p"/settings/calendars"
  defp back(calendar), do: ~p"/settings/calendars/#{calendar}"

  defp country_code(nil), do: nil
  defp country_code(calendar), do: (calendar.parent || calendar).country_code

  defp change(nil, organisation, params), do: Org.change_calendar(organisation, params)
  defp change(calendar, _organisation, params), do: Changeset.change(calendar, params)

  defp write(%{calendar: nil} = assigns, params) do
    Org.create_calendar(assigns.organisation, assigns.current_person, params)
  end

  defp write(assigns, params) do
    Org.update_calendar(assigns.calendar, assigns.current_person, params)
  end

  defp saved(socket, {:ok, calendar}) do
    socket |> put_flash(:info, "Saved.") |> push_navigate(to: ~p"/settings/calendars/#{calendar}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
