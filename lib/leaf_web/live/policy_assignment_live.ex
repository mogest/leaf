defmodule LeafWeb.PolicyAssignmentLive do
  @moduledoc """
  Putting somebody on a leave policy from a date.

  Assignments supersede rather than replace, so moving somebody between policies is one of these
  rather than an edit. One entered by mistake comes off their page.
  """

  use LeafWeb, :live_view

  alias Leaf.People
  alias Leaf.Policies

  @impl Phoenix.LiveView
  def mount(%{"person_id" => id}, _session, socket) do
    {:ok, person} = People.fetch_person(id)
    opening = %{"effective_from" => to_string(person.employment_start_date)}

    {:ok,
     socket
     |> assign(:page_title, "Assign a leave policy")
     |> assign(:person, person)
     |> assign(:policies, policies(person))
     |> assign(:form, to_form(People.change_policy_assignment(person, opening)))}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"person_policy_assignment" => params}, socket) do
    changeset = People.change_policy_assignment(socket.assigns.person, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"person_policy_assignment" => params}, socket) do
    assignment =
      People.create_policy_assignment(
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
        <h1>Assign a leave policy</h1>
        <.link navigate={~p"/people/#{@person}"}>{@person.name}</.link>
      </header>

      <.form id="policy-assignment" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>What they are entitled to, and from when</h2>
          </header>
          <.input
            field={@form[:leave_policy_id]}
            type="select"
            label="Leave policy"
            prompt="Choose one"
            options={@policies}
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

  defp policies(person) do
    person.organisation_id
    |> Policies.leave_policies()
    |> Enum.filter(&is_nil(&1.archived_at))
    |> Enum.map(&{&1.name, &1.id})
  end

  defp saved(socket, {:ok, _assignment}) do
    socket
    |> put_flash(:info, "They are on that policy.")
    |> push_navigate(to: ~p"/people/#{socket.assigns.person}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
