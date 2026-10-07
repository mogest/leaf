defmodule LeafWeb.CalendarLive do
  @moduledoc """
  One calendar: the public holidays entered on it, and the regions inside it.

  Only what is local to the calendar is entered here — a region's page holds its anniversary days
  and nothing its country already observes. Holidays go on the dates they are observed rather than
  the dates they fall, since that is the day nobody works. A holiday entered in error is deleted
  rather than superseded — left there it would keep counting against every public holiday allowance
  drawn from the calendar.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

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
  def handle_event("validate-holiday", %{"public_holiday" => params}, socket) do
    changeset = Org.change_public_holiday(socket.assigns.calendar, params)

    {:noreply, assign(socket, :holiday_form, to_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save-holiday", %{"public_holiday" => params}, socket) do
    created =
      Org.create_public_holiday(socket.assigns.calendar, socket.assigns.current_person, params)

    {:noreply, added(socket, created)}
  end

  @role :admin
  def handle_event("remove", %{"id" => id}, socket) do
    {:noreply, remove(socket, Org.fetch_public_holiday(socket.assigns.calendar, id))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <nav aria-label="Breadcrumb">
          <.link navigate={~p"/settings/calendars"}>Calendars</.link>
          <.link :if={@country} navigate={~p"/settings/calendars/#{@country}"}>{@country.name}</.link>
        </nav>
        <h1>{@calendar.name}</h1>
        <.link class="button" navigate={~p"/settings/calendars/#{@calendar}/edit"}>Edit</.link>
      </header>

      <section>
        <header>
          <h2>Public holidays</h2>
        </header>
        <p :if={@country}>
          Only what is local to {@calendar.name} goes here — everybody on it
          observes {@country.name}'s holidays as well as these.
        </p>
        <table :if={@holidays != []}>
          <thead>
            <tr>
              <th scope="col">Date</th>
              <th scope="col">Name</th>
              <td></td>
            </tr>
          </thead>
          <tbody>
            <tr :for={holiday <- @holidays}>
              <td>{holiday.date}</td>
              <th scope="row">{holiday.name}</th>
              <td>
                <Parts.row_menu id={"holiday-#{holiday.id}"} label={holiday.name}>
                  <button
                    type="button"
                    phx-click="remove"
                    phx-value-id={holiday.id}
                    data-confirm="Remove this holiday? Every allowance drawn from this calendar is recounted."
                  >
                    Remove
                  </button>
                </Parts.row_menu>
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@holidays == []}>No holidays on this calendar yet.</p>
      </section>

      <aside>
        <section :if={!@country}>
          <header>
            <h2>Regions</h2>
            <.link class="add" navigate={~p"/settings/calendars/#{@calendar}/regions/new"}>Add</.link>
          </header>
          <ul :if={@regions != []}>
            <li :for={region <- @regions}>
              <.link navigate={~p"/settings/calendars/#{region}"}>{region.name}</.link>
            </li>
          </ul>
          <p :if={@regions == []}>No regions, so everybody here observes the same days.</p>
        </section>

        <.form
          id="new-holiday"
          for={@holiday_form}
          phx-change="validate-holiday"
          phx-submit="save-holiday"
        >
          <section>
            <header>
              <h2>Add a holiday</h2>
            </header>
            <.input field={@holiday_form[:date]} type="date" label="Date" />
            <.input field={@holiday_form[:name]} type="text" label="Name" />
          </section>

          <footer>
            <p>A holiday goes on the date it is observed — a Saturday one on the Monday after.</p>
            <button class="button" type="submit">Add it</button>
          </footer>
        </.form>
      </aside>
    </Layouts.app>
    """
  end

  defp opened(socket, calendar) do
    socket
    |> assign(:page_title, calendar.name)
    |> assign(:calendar, calendar)
    |> assign(:country, calendar.parent)
    |> assign(:regions, calendar.regions)
    |> blank()
    |> listed()
  end

  defp unknown(socket) do
    socket
    |> put_flash(:error, "That calendar is not on record.")
    |> push_navigate(to: ~p"/settings/calendars")
  end

  defp listed(socket) do
    holidays = Org.public_holidays(socket.assigns.calendar.id)

    assign(socket, :holidays, Enum.map(holidays, &row/1))
  end

  defp blank(socket) do
    assign(
      socket,
      :holiday_form,
      to_form(Org.change_public_holiday(socket.assigns.calendar, %{}))
    )
  end

  defp row(holiday) do
    %{id: holiday.id, date: Wording.date(holiday.date), name: holiday.name}
  end

  defp added(socket, {:ok, holiday}) do
    socket |> put_flash(:info, "#{holiday.name} is on the calendar.") |> blank() |> listed()
  end

  defp added(socket, {:error, changeset}) do
    assign(socket, :holiday_form, to_form(changeset, action: :validate))
  end

  defp remove(socket, :error) do
    put_flash(socket, :error, "That holiday is not on this calendar.")
  end

  defp remove(socket, {:ok, holiday}) do
    written = Org.delete_public_holiday(holiday, socket.assigns.current_person)

    socket |> removed(written) |> listed()
  end

  defp removed(socket, {:ok, _holiday}), do: put_flash(socket, :info, "Removed.")

  defp removed(socket, {:error, _changeset}) do
    put_flash(socket, :error, "That would not come off the calendar.")
  end
end
