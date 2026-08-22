defmodule LeafWeb.WorkPatternLive do
  @moduledoc """
  The hours somebody works on each day of the week, from a date.

  A new pattern supersedes whatever they were on; amending one is how an FTE that was wrong all
  year is put right, and every figure that leant on it follows (§4.4).
  """

  use LeafWeb, :live_view

  alias Leaf.People

  @weekdays [
    {:monday_hours, "Monday"},
    {:tuesday_hours, "Tuesday"},
    {:wednesday_hours, "Wednesday"},
    {:thursday_hours, "Thursday"},
    {:friday_hours, "Friday"},
    {:saturday_hours, "Saturday"},
    {:sunday_hours, "Sunday"}
  ]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok, person} = People.fetch_person(params["person_id"])
    pattern = amending(socket.assigns.live_action, params)

    {:ok,
     socket
     |> assign(:page_title, title(socket.assigns.live_action))
     |> assign(:title, title(socket.assigns.live_action))
     |> assign(:person, person)
     |> assign(:pattern, pattern)
     |> assign(:subject, pattern || person)
     |> assign(:weekdays, @weekdays)
     |> assign(
       :form,
       to_form(People.change_work_pattern(pattern || person, opening(pattern, person)))
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"work_pattern" => params}, socket) do
    changeset = People.change_work_pattern(socket.assigns.subject, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"work_pattern" => params}, socket) do
    {:noreply, saved(socket, write(socket.assigns, params))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="people" viewer={@viewer}>
      <header>
        <h1>{@title}</h1>
        <.link navigate={~p"/people/#{@person}"}>{@person.name}</.link>
      </header>

      <.form id="work-pattern" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Hours a day</h2>
            <p>a day of no hours is one they do not work</p>
          </header>
          <.input field={@form[:effective_from]} type="date" label="From" />
          <.input :for={{field, day} <- @weekdays} field={@form[field]} type="text" label={day} />
        </section>

        <footer>
          <button class="button" type="submit">Save</button>
          <.link navigate={~p"/people/#{@person}"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp amending(:new, _params), do: nil

  defp amending(:edit, %{"id" => id}) do
    {:ok, pattern} = People.fetch_work_pattern(id)

    pattern
  end

  defp title(:new), do: "Add a work pattern"
  defp title(:edit), do: "Amend a work pattern"

  # A first pattern almost always starts the day the person did, so that is what is offered.
  defp opening(nil, person), do: %{"effective_from" => to_string(person.employment_start_date)}
  defp opening(_pattern, _person), do: %{}

  defp write(%{pattern: nil} = assigns, params) do
    People.create_work_pattern(assigns.person, assigns.current_person, params)
  end

  defp write(assigns, params) do
    People.update_work_pattern(assigns.pattern, assigns.current_person, params)
  end

  defp saved(socket, {:ok, _pattern}) do
    socket
    |> put_flash(:info, "The work pattern is on record.")
    |> push_navigate(to: ~p"/people/#{socket.assigns.person}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
