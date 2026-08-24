defmodule LeafWeb.CalendarAssignmentLive do
  @moduledoc """
  Putting somebody on a calendar from a date.

  Which holidays a person observes, and what zone they are in, is where they are — so somebody who
  moves gets another of these rather than an edit. One entered by mistake comes off their page.
  """

  use LeafWeb, :live_view

  alias Leaf.Org
  alias Leaf.People

  @impl Phoenix.LiveView
  def mount(%{"person_id" => id}, _session, socket) do
    {:ok, person} = People.fetch_person(id)
    opening = %{"effective_from" => to_string(person.employment_start_date)}

    {:ok,
     socket
     |> assign(:page_title, "Assign a calendar")
     |> assign(:person, person)
     |> assign(:calendars, calendars(person))
     |> assign(:form, to_form(People.change_calendar_assignment(person, opening)))}
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"person_calendar" => params}, socket) do
    changeset = People.change_calendar_assignment(socket.assigns.person, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save", %{"person_calendar" => params}, socket) do
    assignment =
      People.create_calendar_assignment(
        socket.assigns.person,
        socket.assigns.current_person,
        params
      )

    {:noreply, saved(socket, assignment)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="people" viewer={@viewer}>
      <header>
        <h1>Assign a calendar</h1>
        <.link navigate={~p"/people/#{@person}"}>{@person.name}</.link>
      </header>

      <.form id="calendar-assignment" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Where they are, and from when</h2>
          </header>
          <.input
            field={@form[:calendar_id]}
            type="select"
            label="Calendar"
            prompt="Choose one"
            options={@calendars}
          />
          <.input field={@form[:effective_from]} type="date" label="From" />
        </section>

        <footer>
          <button class="button" type="submit">Assign</button>
          <.link navigate={~p"/people/#{@person}"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp calendars(person) do
    person.organisation_id |> Org.calendars() |> Enum.map(&{Wording.calendar(&1), &1.id})
  end

  defp saved(socket, {:ok, _assignment}) do
    socket
    |> put_flash(:info, "They are on that calendar.")
    |> push_navigate(to: ~p"/people/#{socket.assigns.person}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
