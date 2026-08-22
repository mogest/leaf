defmodule LeafWeb.PeopleLive do
  @moduledoc "Everyone the organisation tracks leave for, and how much of a week each of them works."

  use LeafWeb, :live_view

  alias Leaf.Org
  alias Leaf.People

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)
    today = Date.utc_today()
    people = People.people(organisation.id)
    names = Map.new(people, &{&1.id, &1.name})

    {:ok,
     socket
     |> assign(:page_title, "People")
     |> assign(:people, Enum.map(people, &row(&1, organisation, names, today)))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="people" current_person={@current_person}>
      <header>
        <h1>People</h1>
        <.link class="button" navigate={~p"/people/new"}>Add somebody</.link>
      </header>

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
    </Layouts.app>
    """
  end

  defp row(person, organisation, names, today) do
    %{
      name: person.name,
      path: ~p"/people/#{person}",
      email: person.email,
      admin?: person.role == :admin,
      employment: employment(person),
      hours: hours(person, organisation, today),
      manager: names[person.manager_id],
      tone: tone(person, today)
    }
  end

  defp employment(%{employment_end_date: nil} = person) do
    "from #{Wording.date(person.employment_start_date)}"
  end

  defp employment(person) do
    "#{Wording.date(person.employment_start_date)} – #{Wording.date(person.employment_end_date)}"
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
