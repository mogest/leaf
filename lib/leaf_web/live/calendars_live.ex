defmodule LeafWeb.CalendarsLive do
  @moduledoc """
  The calendars the organisation holds, each country followed by the regions inside it.

  A country is added from here, a region on its country's own page, which is where the country and
  the zone it starts from are.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Org

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Calendars") |> listed()}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <h1>Calendars</h1>
        <.link class="button" navigate={~p"/settings/calendars/new"}>Add</.link>
      </header>

      <Parts.settings_nav here="calendars" />

      <section>
        <table>
          <thead>
            <tr>
              <th scope="col">Name</th>
              <th scope="col">Country</th>
              <th scope="col">Time zone</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={calendar <- @calendars}>
              <th scope="row"><.link navigate={calendar.path}>{calendar.name}</.link></th>
              <td>{calendar.country_code}</td>
              <td>{calendar.time_zone}</td>
            </tr>
          </tbody>
        </table>
        <p :if={@calendars == []}>No calendars yet, so nobody observes any public holidays.</p>
      </section>
    </Layouts.app>
    """
  end

  defp listed(socket) do
    calendars = Org.calendars(socket.assigns.current_person.organisation_id)

    assign(socket, :calendars, Enum.map(calendars, &row/1))
  end

  defp row(calendar) do
    %{
      name: Wording.calendar(calendar),
      country_code: country_code(calendar.country_code),
      time_zone: calendar.time_zone,
      path: ~p"/settings/calendars/#{calendar}"
    }
  end

  defp country_code(nil), do: nil
  defp country_code(code), do: String.upcase(code)
end
