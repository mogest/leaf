defmodule LeafWeb.CalendarLive do
  @moduledoc """
  One holiday calendar: its name, and every public holiday on it.

  Holidays go on the dates they are observed rather than the dates they fall, since that is the
  day nobody works. A holiday entered in error is deleted rather than superseded — left there it
  would keep counting against every public holiday allowance drawn from the calendar.
  """

  use LeafWeb, :live_view

  alias Leaf.Org

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    {:ok, calendar} = Org.fetch_holiday_calendar(id)

    {:ok,
     socket
     |> assign(:page_title, calendar.name)
     |> assign(:calendar, calendar)
     |> assign(:form, to_form(Org.change_holiday_calendar(calendar, %{})))
     |> blank()
     |> listed()}
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate-calendar", %{"holiday_calendar" => params}, socket) do
    changeset = Org.change_holiday_calendar(socket.assigns.calendar, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save-calendar", %{"holiday_calendar" => params}, socket) do
    written =
      Org.update_holiday_calendar(socket.assigns.calendar, socket.assigns.current_person, params)

    {:noreply, renamed(socket, written)}
  end

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
        <.link navigate={~p"/settings/calendars"}>Holiday calendars</.link>
        <h1>{@calendar.name}</h1>
      </header>

      <section>
        <header>
          <h2>Public holidays</h2>
          <p>{@counted}</p>
        </header>
        <table :if={@holidays != []}>
          <thead>
            <tr>
              <th scope="col">Date</th>
              <th scope="col">Name</th>
              <th scope="col"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={holiday <- @holidays}>
              <td>{holiday.date}</td>
              <th scope="row">{holiday.name}</th>
              <td>
                <button
                  type="button"
                  phx-click="remove"
                  phx-value-id={holiday.id}
                  data-confirm="Remove this holiday? Every allowance drawn from this calendar is recounted."
                >
                  Remove
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@holidays == []}>No holidays on this calendar yet.</p>
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
            <p>on the date it is observed, not the date it falls</p>
          </header>
          <.input field={@holiday_form[:date]} type="date" label="Date" />
          <.input field={@holiday_form[:name]} type="text" label="Name" />
        </section>

        <footer>
          <button class="button" type="submit">Add it</button>
        </footer>
      </.form>

      <.form id="calendar" for={@form} phx-change="validate-calendar" phx-submit="save-calendar">
        <section>
          <header>
            <h2>The calendar itself</h2>
          </header>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:country_code]} type="text" label="Country code, two letters" />
        </section>

        <footer>
          <button class="button" type="submit">Save</button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp listed(socket) do
    holidays = Org.public_holidays(socket.assigns.calendar.id)

    socket
    |> assign(:holidays, Enum.map(holidays, &row/1))
    |> assign(:counted, counted(holidays))
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

  defp counted([]), do: "none yet"
  defp counted([_one]), do: "one"
  defp counted(holidays), do: "#{length(holidays)}, #{spanning(holidays)}"

  defp spanning(holidays) do
    dates = Enum.map(holidays, & &1.date)

    "#{Enum.min(dates, Date).year} to #{Enum.max(dates, Date).year}"
  end

  defp renamed(socket, {:ok, calendar}) do
    socket
    |> assign(:calendar, calendar)
    |> assign(:form, to_form(Org.change_holiday_calendar(calendar, %{})))
    |> put_flash(:info, "Saved.")
  end

  defp renamed(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
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
