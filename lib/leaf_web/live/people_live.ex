defmodule LeafWeb.PeopleLive do
  @moduledoc "Everyone the viewer oversees, and how much of a week each of them works."

  use LeafWeb, :live_view

  alias Leaf.Org
  alias Leaf.People

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, listed(socket, People.overseen(socket.assigns.current_person))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="people" viewer={@viewer}>
      <header>
        <h1>People</h1>
        <.link :if={@viewer.admin?} class="button" navigate={~p"/people/new"}>Add</.link>
      </header>

      <div>
        <table>
          <thead>
            <tr>
              <th scope="col">Name</th>
              <th scope="col">Email</th>
              <th scope="col">Employment</th>
              <th scope="col">Hours a week</th>
              <th scope="col">Manager</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={person <- @people} data-tone={person.tone}>
              <th scope="row">
                <.link navigate={person.path}>{person.name}</.link>
                <small :if={person.admin?}>administrator</small>
              </th>
              <td>{person.email}</td>
              <td>{person.employment}</td>
              <td>{person.hours}</td>
              <td>{person.manager}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  defp listed(socket, []) do
    socket |> put_flash(:error, "Nobody reports to you.") |> push_navigate(to: ~p"/")
  end

  defp listed(socket, people) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)
    today = People.today(socket.assigns.current_person)
    names = Map.new(People.people(organisation.id), &{&1.id, &1.name})

    socket
    |> assign(:page_title, "People")
    |> assign(:people, Enum.map(people, &row(&1, organisation, names, today)))
  end

  defp row(person, organisation, names, today) do
    %{
      name: person.name,
      path: ~p"/people/#{person}",
      email: person.email,
      admin?: person.role == :admin,
      employment: Wording.employment(person),
      hours: hours(person, organisation, today),
      manager: names[person.manager_id],
      tone: tone(person, today)
    }
  end

  defp hours(person, organisation, today) do
    case People.fetch_work_pattern_on(person, today) do
      {:ok, pattern} -> weekly(pattern, organisation)
      :error -> "no work pattern"
    end
  end

  defp weekly(pattern, organisation) do
    weekly = People.weekly_hours(pattern)
    fte = People.fte(pattern, organisation.full_time_week_hours)

    "#{Wording.number(weekly)} (#{Wording.number(fte)} FTE)"
  end

  defp tone(%{employment_end_date: nil}, _today), do: nil

  defp tone(person, today) do
    case Date.before?(person.employment_end_date, today) do
      true -> "past"
      false -> nil
    end
  end
end
