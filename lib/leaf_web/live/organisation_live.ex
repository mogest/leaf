defmodule LeafWeb.OrganisationLive do
  @moduledoc """
  The organisation's own settings, and the way in to everything else configured here.

  `tracked_from` is the one setting that re-works every balance in the organisation at once
  (§4.10), so the form says so where it is changed rather than anywhere else.
  """

  use LeafWeb, :live_view

  alias Leaf.Org

  @months [
    {"January", "1"},
    {"February", "2"},
    {"March", "3"},
    {"April", "4"},
    {"May", "5"},
    {"June", "6"},
    {"July", "7"},
    {"August", "8"},
    {"September", "9"},
    {"October", "10"},
    {"November", "11"},
    {"December", "12"}
  ]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:organisation, organisation)
     |> assign(:months, @months)
     |> assign(:form, to_form(Org.change_organisation(organisation, %{})))}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"organisation" => params}, socket) do
    changeset = Org.change_organisation(socket.assigns.organisation, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"organisation" => params}, socket) do
    saved =
      Org.update_organisation(socket.assigns.organisation, socket.assigns.current_person, params)

    {:noreply, saved(socket, saved)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" current_person={@current_person}>
      <header>
        <h1>Settings</h1>
      </header>

      <Parts.settings_nav here="organisation" />

      <.form id="organisation" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>The organisation</h2>
          </header>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input
            field={@form[:full_time_week_hours]}
            type="text"
            label="Hours in a full-time week"
          />
          <.input field={@form[:standard_day_hours]} type="text" label="Hours in a standard day" />
          <.input
            field={@form[:year_start_month]}
            type="select"
            label="The financial year starts in"
            options={@months}
          />
        </section>

        <section>
          <header>
            <h2>Tracking</h2>
            <p>moving this re-works every balance at once</p>
          </header>
          <.input field={@form[:tracked_from]} type="date" label="Leave has been tracked here from" />
          <p>
            Nothing accrues, is granted or lapses before that date — the opening balances account
            for everything up to it. Leave dated earlier still counts, and draws down what was
            brought in.
          </p>
        </section>

        <footer>
          <button class="button" type="submit">Save</button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp saved(socket, {:ok, organisation}) do
    socket
    |> assign(:organisation, organisation)
    |> assign(:form, to_form(Org.change_organisation(organisation, %{})))
    |> put_flash(:info, "Saved.")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
