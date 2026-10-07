defmodule LeafWeb.WorkPatternLive do
  @moduledoc """
  The hours somebody works on each day of the week, from a date.

  A new pattern supersedes whatever they were on; amending one is how an FTE that was wrong all
  year is put right, and every figure that leant on it follows (§4.4).
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Changeset
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
    case People.fetch_person(params["person_id"]) do
      {:ok, person} ->
        {:ok, opened(socket, person, amending(socket.assigns.live_action, person, params))}

      :error ->
        {:ok, unknown(socket)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"work_pattern" => params} = form_params, socket) do
    %{pattern: pattern, person: person, shape: shape} = socket.assigns
    # The params come from the form as it stood, before any new shape was picked.
    changeset = change(pattern, person, shaped(shape, params))

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign(:shape, Map.get(form_params, "shape", shape))}
  end

  @role :admin
  def handle_event("save", %{"work_pattern" => params}, socket) do
    {:noreply, saved(socket, write(socket.assigns, shaped(socket.assigns.shape, params)))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="people" viewer={@viewer}>
      <header>
        <nav aria-label="Breadcrumb">
          <.link navigate={~p"/people"}>People</.link>
          <.link navigate={~p"/people/#{@person}"}>{@person.name}</.link>
        </nav>
        <h1>{@title}</h1>
      </header>

      <.form id="work-pattern" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Hours</h2>
          </header>
          <.input field={@form[:effective_from]} type="date" label="From" />
          <fieldset :if={@live_action == :new}>
            <legend>Works</legend>
            <label>
              <input type="radio" name="shape" value="weekdays" checked={@shape == "weekdays"} />
              The same hours every weekday
            </label>
            <label>
              <input type="radio" name="shape" value="by-day" checked={@shape == "by-day"} />
              Different hours by day
            </label>
          </fieldset>
          <.input
            :if={@shape == "weekdays"}
            field={@form[:monday_hours]}
            label="Hours each weekday"
            inputmode="decimal"
          />
          <fieldset :if={@shape == "by-day"}>
            <legend>Hours each day</legend>
            <.input
              :for={{field, day} <- @weekdays}
              field={named(@form[field], day)}
              label={String.slice(day, 0, 3)}
              inputmode="decimal"
            />
          </fieldset>
        </section>

        <footer>
          <button class="button" type="submit">Save</button>
          <.link navigate={~p"/people/#{@person}"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp amending(:new, _person, _params), do: {:ok, nil}
  defp amending(:edit, person, %{"id" => id}), do: People.fetch_work_pattern(person, id)

  defp opened(socket, person, {:ok, pattern}) do
    socket
    |> assign(:page_title, title(socket.assigns.live_action))
    |> assign(:title, title(socket.assigns.live_action))
    |> assign(:person, person)
    |> assign(:pattern, pattern)
    |> assign(:weekdays, @weekdays)
    |> assign(:shape, shape(socket.assigns.live_action))
    |> assign(:form, to_form(change(pattern, person, opening(pattern, person))))
  end

  defp opened(socket, person, :error) do
    socket
    |> put_flash(:error, "That work pattern is not theirs.")
    |> push_navigate(to: ~p"/people/#{person}")
  end

  defp unknown(socket) do
    socket |> put_flash(:error, "That person is not on record.") |> push_navigate(to: ~p"/people")
  end

  defp title(:new), do: "Add a work pattern"
  defp title(:edit), do: "Edit a work pattern"

  defp named(field, day) do
    %{
      field
      | errors: Enum.map(field.errors, fn {message, opts} -> {"#{day} #{message}", opts} end)
    }
  end

  defp shape(:new), do: "weekdays"
  defp shape(:edit), do: "by-day"

  defp shaped("weekdays", %{"monday_hours" => ""} = params), do: params

  defp shaped("weekdays", %{"monday_hours" => hours} = params) do
    Map.merge(params, %{
      "tuesday_hours" => hours,
      "wednesday_hours" => hours,
      "thursday_hours" => hours,
      "friday_hours" => hours,
      "saturday_hours" => "0",
      "sunday_hours" => "0"
    })
  end

  defp shaped(_shape, params), do: params

  defp opening(nil, person),
    do: %{"effective_from" => to_string(starting(person, People.work_patterns(person)))}

  defp opening(_pattern, _person), do: %{}

  # A first pattern almost always starts the day the person did; a later one, about now.
  defp starting(person, []), do: person.employment_start_date
  defp starting(person, _patterns), do: People.today(person)

  defp change(nil, person, params), do: People.change_work_pattern(person, params)
  defp change(pattern, _person, params), do: Changeset.change(pattern, params)

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
