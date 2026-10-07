defmodule LeafWeb.PersonFormLive do
  @moduledoc """
  Adding somebody, and correcting what is on record about them.

  A start date is the anchor for everything anniversary-shaped, so correcting one here moves every
  grant that hangs off it. That is the point of §4.4, and it is why this is an ordinary form.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Changeset
  alias Leaf.Org
  alias Leaf.People

  @roles [{"Member", "member"}, {"Administrator", "admin"}]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case amending(socket.assigns.live_action, params) do
      {:ok, person} -> {:ok, opened(socket, person)}
      :error -> {:ok, unknown(socket)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"person" => params}, socket) do
    changeset = change(socket.assigns.person, socket.assigns.organisation, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save", %{"person" => params}, socket) do
    {:noreply, saved(socket, write(socket.assigns, params))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="people" viewer={@viewer}>
      <header>
        <nav aria-label="Breadcrumb">
          <.link navigate={~p"/people"}>People</.link>
          <.link :if={@person} navigate={~p"/people/#{@person}"}>{@person.name}</.link>
        </nav>
        <h1>{@title}</h1>
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
          <.input field={@form[:employee_number]} type="text" label="Employee number" />
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

  defp amending(:new, _params), do: {:ok, nil}
  defp amending(:edit, %{"person_id" => id}), do: People.fetch_person(id)

  defp opened(socket, person) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)

    socket
    |> assign(:page_title, title(socket.assigns.live_action))
    |> assign(:title, title(socket.assigns.live_action))
    |> assign(:person, person)
    |> assign(:organisation, organisation)
    |> assign(:back, back(person))
    |> assign(:roles, @roles)
    |> assign(:managers, managers(organisation, person))
    |> assign(:form, to_form(change(person, organisation, %{})))
  end

  defp unknown(socket) do
    socket |> put_flash(:error, "That person is not on record.") |> push_navigate(to: ~p"/people")
  end

  defp title(:new), do: "Add somebody"
  defp title(:edit), do: "Edit somebody"

  defp back(nil), do: ~p"/people"
  defp back(person), do: ~p"/people/#{person}"

  # Nobody may manage themselves, so an existing person is not offered as their own manager.
  defp managers(organisation, person) do
    organisation.id
    |> People.people()
    |> Enum.reject(&(person && &1.id == person.id))
    |> Enum.map(&{&1.name, &1.id})
  end

  defp change(nil, organisation, params), do: People.change_person(organisation, params)
  defp change(person, _organisation, params), do: Changeset.change(person, params)

  defp write(%{person: nil} = assigns, params) do
    People.create_person(assigns.organisation, assigns.current_person, params)
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
