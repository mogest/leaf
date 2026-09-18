defmodule LeafWeb.AssignmentLive do
  @moduledoc """
  Putting somebody on a leave policy, or on a calendar, from a date.

  Either supersedes rather than replaces, so moving somebody between policies, or to where other
  holidays are observed, is another of these rather than an edit. One entered by mistake comes off
  their page.
  """

  use LeafWeb, :live_view

  alias Leaf.Org
  alias Leaf.People
  alias Leaf.Policies

  @kinds %{
    policy: %{
      title: "Assign a leave policy",
      heading: "What they are entitled to, and from when",
      label: "Leave policy",
      field: :leave_policy_id,
      confirmation: "They are on that policy."
    },
    calendar: %{
      title: "Assign a calendar",
      heading: "Where they are, and from when",
      label: "Calendar",
      field: :calendar_id,
      confirmation: "They are on that calendar."
    }
  }

  @impl Phoenix.LiveView
  def mount(%{"person_id" => id}, _session, socket) do
    {:ok, person} = People.fetch_person(id)
    action = socket.assigns.live_action
    kind = @kinds[action]
    opening = %{"effective_from" => to_string(person.employment_start_date)}

    {:ok,
     socket
     |> assign(:page_title, kind.title)
     |> assign(:kind, kind)
     |> assign(:person, person)
     |> assign(:options, options(action, person))
     |> assign(:form, as_form(change(action, person, opening)))}
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"assignment" => params}, socket) do
    changeset = change(socket.assigns.live_action, socket.assigns.person, params)

    {:noreply, assign(socket, :form, as_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save", %{"assignment" => params}, socket) do
    {:noreply, saved(socket, create(socket.assigns, params))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="people" viewer={@viewer}>
      <header>
        <h1>{@kind.title}</h1>
        <.link navigate={~p"/people/#{@person}"}>{@person.name}</.link>
      </header>

      <.form id={"#{@live_action}-assignment"} for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>{@kind.heading}</h2>
          </header>
          <.input
            field={@form[@kind.field]}
            type="select"
            label={@kind.label}
            prompt="Choose one"
            options={@options}
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

  defp options(:policy, person) do
    person.organisation_id
    |> Policies.leave_policies_offered()
    |> Enum.map(&{&1.name, &1.id})
  end

  defp options(:calendar, person) do
    person.organisation_id |> Org.calendars() |> Enum.map(&{Wording.calendar(&1), &1.id})
  end

  defp change(:policy, person, attrs), do: People.change_policy_assignment(person, attrs)
  defp change(:calendar, person, attrs), do: People.change_calendar_assignment(person, attrs)

  defp create(%{live_action: :policy} = assigns, params) do
    People.create_policy_assignment(assigns.person, assigns.current_person, params)
  end

  defp create(%{live_action: :calendar} = assigns, params) do
    People.create_calendar_assignment(assigns.person, assigns.current_person, params)
  end

  # The two schemas would otherwise name the params after themselves, and each event would need a
  # clause per schema to match the name.
  defp as_form(changeset, opts \\ []), do: to_form(changeset, Keyword.put(opts, :as, :assignment))

  defp saved(socket, {:ok, _assignment}) do
    socket
    |> put_flash(:info, socket.assigns.kind.confirmation)
    |> push_navigate(to: ~p"/people/#{socket.assigns.person}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, as_form(changeset, action: :validate))
  end
end
