defmodule LeafWeb.WhoIsAwayLive do
  @moduledoc """
  A month of the whole organisation at once: a row each, a column a day.

  The cells are the days a calendar is drawn from, so a person's leave, their public holidays and
  the days they do not work read here as they read on their own page. What the viewer may not see
  of somebody else's record is decided in `Leaf.Leave`, not here.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave
  alias Leaf.People

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    today = Date.utc_today()
    from = from(params["month"], today)
    range = Date.range(from, Date.end_of_month(from))

    {:ok,
     socket
     |> assign(:page_title, "Who's away")
     |> assign(:today, today)
     |> assign(:month, Calendar.strftime(from, "%B %Y"))
     |> assign(:earlier, step(from, -1))
     |> assign(:later, step(from, 1))
     |> assign(:dates, Enum.map(range, &heading(&1, today)))
     |> assign(:rows, rows(socket, range, today))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="who-is-away" viewer={@viewer}>
      <header>
        <h1>Who's away</h1>
      </header>

      <section>
        <header>
          <h2>{@month}</h2>
          <Parts.steps earlier={@earlier} later={@later} what="month" />
        </header>

        <div>
          <table>
            <thead>
              <tr>
                <th scope="col">Person</th>
                <th :for={date <- @dates} scope="col" data-today={date.today?}>
                  <abbr title={date.title}>{date.number}</abbr>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @rows}>
                <th scope="row">
                  <.link :if={row.path} navigate={row.path}>{row.name}</.link>
                  <span :if={!row.path}>{row.name}</span>
                </th>
                <td
                  :for={day <- row.days}
                  data-working={day.working}
                  data-leave={day.leave}
                  data-holiday={day.holiday}
                  data-today={day.today?}
                >
                  <abbr :if={day.title} title={day.title}>·</abbr>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <ul class="legend">
          <li data-leave="approved">Away</li>
          <li data-leave="pending">Asked for</li>
          <li data-holiday>Public holiday</li>
          <li>Faded days are ones they do not work</li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  defp rows(socket, range, today) do
    viewer = socket.assigns.current_person

    viewer.organisation_id
    |> People.people()
    |> Leave.away(viewer, range)
    |> Enum.map(&row(&1, viewer, today))
  end

  defp from(nil, today), do: Date.beginning_of_month(today)

  defp from(named, today) do
    case Date.from_iso8601("#{named}-01") do
      {:ok, date} -> date
      {:error, _reason} -> Date.beginning_of_month(today)
    end
  end

  defp step(from, months) do
    named = from |> Date.shift(month: months) |> Calendar.strftime("%Y-%m")

    ~p"/away?month=#{named}"
  end

  defp heading(date, today) do
    %{
      number: date.day,
      title: Wording.weekday(date),
      today?: date == today
    }
  end

  # A name is a link only where the reader may open the page behind it (§5.9).
  defp row({person, days}, viewer, today) do
    %{
      name: person.name,
      path: People.oversees?(viewer, person) && ~p"/people/#{person}",
      days: Enum.map(days, &cell(&1, today))
    }
  end

  defp cell(day, today) do
    %{
      working: working(day.working?),
      leave: day.leave,
      holiday: day.holiday,
      today?: day.date == today,
      title: day.holiday
    }
  end

  defp working(true), do: nil
  defp working(false), do: "no"
end
