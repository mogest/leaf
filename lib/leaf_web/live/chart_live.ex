defmodule LeafWeb.ChartLive do
  @moduledoc "Who reports to whom: everyone employed today, under their manager."

  use LeafWeb, :live_view

  alias Leaf.People

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    viewer = socket.assigns.current_person
    chart = People.chart(viewer.organisation_id, People.today(viewer))

    {:ok,
     socket
     |> assign(:page_title, "Org chart")
     |> assign(:chart, Enum.map(chart, &branch(&1, viewer)))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="chart" viewer={@viewer}>
      <header>
        <h1>Org chart</h1>
      </header>

      <.tree branches={@chart} />
    </Layouts.app>
    """
  end

  attr :branches, :list, required: true

  defp tree(assigns) do
    ~H"""
    <ul>
      <li :for={{person, reports} <- @branches}>
        <.link :if={person.path} navigate={person.path}>{person.name}</.link>
        <span :if={!person.path}>{person.name}</span>
        <.tree :if={reports != []} branches={reports} />
      </li>
    </ul>
    """
  end

  defp branch({person, reports}, viewer) do
    {%{name: person.name, path: People.oversees?(viewer, person) && ~p"/people/#{person}"},
     Enum.map(reports, &branch(&1, viewer))}
  end
end
