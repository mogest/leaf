defmodule LeafWeb.PersonFormLive do
  @moduledoc """
  Adding somebody, and correcting what is on record about them.

  A start date is the anchor for everything anniversary-shaped, so correcting one here moves every
  grant that hangs off it. That is the point of §4.4, and it is why this is an ordinary form.
  """

  use LeafWeb, :live_view

  alias Leaf.Org
  alias Leaf.People

  @roles [{"Member", "member"}, {"Administrator", "admin"}]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)
    person = amending(socket.assigns.live_action, params)

    {:ok,
     socket
     |> assign(:page_title, title(socket.assigns.live_action))
     |> assign(:title, title(socket.assigns.live_action))
     |> assign(:person, person)
     |> assign(:subject, person || organisation)
     |> assign(:back, back(person))
     |> assign(:roles, @roles)
     |> assign(:managers, managers(organisation, person))
     |> assign(:form, to_form(People.change_person(person || organisation, %{})))}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"person" => params}, socket) do
    changeset = People.change_person(socket.assigns.subject, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    {:noreply, saved(socket, write(socket.assigns, params))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="people" current_person={@current_person}>
      <header>
        <h1>{@title}</h1>
        <.link navigate={@back}>Back</.link>
      </header>

      <.form id="person" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Who they are</h2>
          </header>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:email]} type="email" label="Email" />
          <.input field={@form[:role]} type="select" label="Role" options={@roles} />
          <.input
            field={@form[:manager_id]}
            type="select"
            label="Manager"
            prompt="Nobody, so an administrator decides"
            options={@managers}
          />
        </section>

        <section>
          <header>
            <h2>Their dates</h2>
          </header>
          <.input field={@form[:employment_start_date]} type="date" label="Employment starts" />
          <.input field={@form[:employment_end_date]} type="date" label="Employment ends" />
          <.input field={@form[:birth_date]} type="date" label="Born" />
        </section>

        <footer>
          <button class="button" type="submit">Save</button>
          <.link navigate={@back}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp amending(:new, _params), do: nil

  defp amending(:edit, %{"person_id" => id}) do
    {:ok, person} = People.fetch_person(id)

    person
  end

  defp title(:new), do: "Add somebody"
  defp title(:edit), do: "Amend somebody"

  defp back(nil), do: ~p"/people"
  defp back(person), do: ~p"/people/#{person}"

  # Nobody may manage themselves, so an existing person is not offered as their own manager.
  defp managers(organisation, person) do
    organisation.id
    |> People.people()
    |> Enum.reject(&(person && &1.id == person.id))
    |> Enum.map(&{&1.name, &1.id})
  end

  defp write(%{person: nil} = assigns, params) do
    People.create_person(assigns.subject, assigns.current_person, params)
  end

  defp write(assigns, params) do
    People.update_person(assigns.person, assigns.current_person, params)
  end

  defp saved(socket, {:ok, person}) do
    socket
    |> put_flash(:info, "#{person.name} is on record.")
    |> push_navigate(to: ~p"/people/#{person}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
