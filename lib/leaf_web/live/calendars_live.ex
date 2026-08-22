defmodule LeafWeb.CalendarsLive do
  @moduledoc "The public holiday calendars the organisation holds, one per country or region."

  use LeafWeb, :live_view

  alias Leaf.Org

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)

    {:ok,
     socket
     |> assign(:page_title, "Holiday calendars")
     |> assign(:organisation, organisation)
     |> assign(:form, to_form(Org.change_holiday_calendar(organisation, %{})))
     |> listed()}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"holiday_calendar" => params}, socket) do
    changeset = Org.change_holiday_calendar(socket.assigns.organisation, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"holiday_calendar" => params}, socket) do
    created =
      Org.create_holiday_calendar(
        socket.assigns.organisation,
        socket.assigns.current_person,
        params
      )

    {:noreply, saved(socket, created)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <h1>Holiday calendars</h1>
      </header>

      <Parts.settings_nav here="calendars" />

      <section>
        <header>
          <h2>Whose holidays are held here</h2>
          <p>one per country, and per region where they differ</p>
        </header>
        <table>
          <thead>
            <tr>
              <th scope="col">Name</th>
              <th scope="col">Country</th>
              <th scope="col">Holidays</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={calendar <- @calendars}>
              <th scope="row"><.link navigate={calendar.path}>{calendar.name}</.link></th>
              <td>{calendar.country_code}</td>
              <td>{calendar.holidays}</td>
            </tr>
          </tbody>
        </table>
        <p :if={@calendars == []}>No calendars yet, so nobody observes any public holidays.</p>
      </section>

      <.form id="new-calendar" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Add a calendar</h2>
          </header>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:country_code]} type="text" label="Country code, two letters" />
        </section>

        <footer>
          <button class="button" type="submit">Add it</button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp listed(socket) do
    calendars = Org.holiday_calendars(socket.assigns.organisation.id)

    assign(socket, :calendars, Enum.map(calendars, &row/1))
  end

  defp row(calendar) do
    %{
      name: calendar.name,
      country_code: String.upcase(calendar.country_code),
      holidays: counted(Org.public_holidays(calendar.id)),
      path: ~p"/settings/calendars/#{calendar}"
    }
  end

  defp counted([]), do: "none yet"
  defp counted([_one]), do: "one"
  defp counted(holidays), do: "#{length(holidays)}"

  defp saved(socket, {:ok, calendar}) do
    push_navigate(socket, to: ~p"/settings/calendars/#{calendar}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
