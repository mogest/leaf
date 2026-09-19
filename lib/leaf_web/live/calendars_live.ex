defmodule LeafWeb.CalendarsLive do
  @moduledoc """
  The calendars the organisation holds, each country followed by the regions inside it.

  A country is added here; a region is added on its country's own page, which is where the country
  and the zone it starts from are.
  """

  use LeafWeb, :live_view

  alias Leaf.Org

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)

    {:ok,
     socket
     |> assign(:page_title, "Calendars")
     |> assign(:organisation, organisation)
     |> assign(:form, to_form(Org.change_calendar(organisation, %{})))
     |> assign(:time_zones, Org.time_zones(nil))
     |> listed()}
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"calendar" => params}, socket) do
    changeset = Org.change_calendar(socket.assigns.organisation, params)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign(:time_zones, Org.time_zones(params["country_code"]))}
  end

  @role :admin
  def handle_event("save", %{"calendar" => params}, socket) do
    created =
      Org.create_calendar(socket.assigns.organisation, socket.assigns.current_person, params)

    {:noreply, saved(socket, created)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <h1>Calendars</h1>
      </header>

      <Parts.settings_nav here="calendars" />

      <section>
        <header>
          <h2>Where people are, and whose holidays they observe</h2>
        </header>
        <table>
          <thead>
            <tr>
              <th scope="col">Name</th>
              <th scope="col">Country</th>
              <th scope="col">Time zone</th>
              <th scope="col">Holidays</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={calendar <- @calendars}>
              <th scope="row"><.link navigate={calendar.path}>{calendar.name}</.link></th>
              <td>{calendar.country_code}</td>
              <td>{calendar.time_zone}</td>
              <td>{calendar.holidays}</td>
            </tr>
          </tbody>
        </table>
        <p :if={@calendars == []}>No calendars yet, so nobody observes any public holidays.</p>
      </section>

      <.form id="new-calendar" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Add a country</h2>
            <p>its regions go on its own page, once it is here</p>
          </header>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:country_code]} type="text" label="Country code, two letters" />
          <.input
            field={@form[:time_zone]}
            type="select"
            label="Time zone"
            prompt="Choose one"
            options={@time_zones}
          />
        </section>

        <footer>
          <button class="button" type="submit">Add it</button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp listed(socket) do
    calendars = Org.calendars(socket.assigns.organisation.id)

    assign(socket, :calendars, Enum.map(calendars, &row/1))
  end

  defp row(calendar) do
    %{
      name: Wording.calendar(calendar),
      country_code: String.upcase(calendar.country_code),
      time_zone: calendar.time_zone,
      holidays: counted(Org.observed_holidays(calendar.id)),
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
