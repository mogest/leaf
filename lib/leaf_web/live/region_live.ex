defmodule LeafWeb.RegionLive do
  @moduledoc """
  Adding a region to a country's calendar.

  A region takes its country's time zone unless it says otherwise, so most are a name. A region of a
  region is not a shape the model has, so a region's id here is as unknown as any other.
  """

  use LeafWeb, :live_view

  alias Leaf.Org

  @impl Phoenix.LiveView
  def mount(%{"calendar_id" => id}, _session, socket) do
    case Org.fetch_calendar(id) do
      {:ok, %{parent_id: nil} = country} -> {:ok, opened(socket, country)}
      _unknown -> {:ok, unknown(socket)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"calendar" => params}, socket) do
    changeset = Org.change_region(socket.assigns.country, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save", %{"calendar" => params}, socket) do
    created = Org.create_region(socket.assigns.country, socket.assigns.current_person, params)

    {:noreply, saved(socket, created)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <h1>Add a region</h1>
        <.link navigate={~p"/settings/calendars/#{@country}"}>{@country.name}</.link>
      </header>

      <.form id="region" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Where it is</h2>
          </header>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input
            field={@form[:time_zone]}
            type="select"
            label="Time zone, where it differs from the country's"
            options={@time_zones}
          />
        </section>

        <footer>
          <button class="button" type="submit">Add it</button>
          <.link navigate={~p"/settings/calendars/#{@country}"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp opened(socket, country) do
    socket
    |> assign(:page_title, "Add a region")
    |> assign(:country, country)
    |> assign(:time_zones, Org.time_zones(country.country_code))
    |> assign(:form, to_form(Org.change_region(country, %{})))
  end

  defp unknown(socket) do
    socket
    |> put_flash(:error, "That is not a country's calendar.")
    |> push_navigate(to: ~p"/settings/calendars")
  end

  defp saved(socket, {:ok, region}) do
    socket
    |> put_flash(:info, "#{region.name} is a region of #{socket.assigns.country.name}.")
    |> push_navigate(to: ~p"/settings/calendars/#{region}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
