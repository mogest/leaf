defmodule LeafWeb.Parts do
  @moduledoc """
  The parts more than one page is assembled from.

  A part here is one the stylesheet had to be told the name of, and everything inside it is
  selected by element. Anything only one page shows belongs to that page instead.
  """

  use Phoenix.Component

  @weekdays [
    {"M", "Monday"},
    {"T", "Tuesday"},
    {"W", "Wednesday"},
    {"T", "Thursday"},
    {"F", "Friday"},
    {"S", "Saturday"},
    {"S", "Sunday"}
  ]

  @doc """
  Months side by side, each day marked with what is on it, and a step either way.

  ## Examples

      <Parts.calendar months={@months} today={@today} earlier={@earlier} later={@later} />

  """
  attr :months, :list, required: true, doc: "the `Leaf.Leave.Month` structs to show"
  attr :today, Date, required: true, doc: "the date to mark as today"
  attr :earlier, :string, required: true, doc: "where the step backwards goes"
  attr :later, :string, required: true, doc: "where the step forwards goes"

  def calendar(assigns) do
    ~H"""
    <section class="calendar">
      <header>
        <h2>Calendar</h2>
      </header>
      <nav>
        <.link navigate={@earlier} aria-label="Earlier months">
          <svg
            width="12"
            height="12"
            viewBox="0 0 16 16"
            fill="none"
            stroke="currentColor"
            stroke-width="1.7"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M10 3L5 8l5 5" />
          </svg>
        </.link>
        <div>
          <table :for={month <- @months}>
            <caption>{Calendar.strftime(month.starts_on, "%B")}</caption>
            <thead>
              <tr>
                <th :for={{initial, weekday} <- weekdays()} scope="col">
                  <abbr title={weekday}>{initial}</abbr>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={week <- month.weeks}>
                <td
                  :for={day <- week}
                  data-working={working(day)}
                  data-leave={leave(day)}
                  data-holiday={holiday(day)}
                  data-today={today?(day, @today)}
                  aria-current={today?(day, @today) && "date"}
                >
                  {number(day)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <.link navigate={@later} aria-label="Later months">
          <svg
            width="12"
            height="12"
            viewBox="0 0 16 16"
            fill="none"
            stroke="currentColor"
            stroke-width="1.7"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M6 3l5 5-5 5" />
          </svg>
        </.link>
      </nav>
      <ul>
        <li data-leave="approved">Approved</li>
        <li data-leave="pending">Waiting</li>
        <li data-holiday>Public holiday</li>
        <li data-today>Today</li>
        <li>Faded days are ones you do not work</li>
      </ul>
    </section>
    """
  end

  defp weekdays, do: @weekdays

  defp working(%{working?: false}), do: "no"
  defp working(_day), do: nil

  defp leave(%{leave: leave}), do: leave
  defp leave(nil), do: nil

  defp holiday(%{holiday: holiday}), do: holiday
  defp holiday(nil), do: nil

  defp today?(%{date: date}, today), do: date == today
  defp today?(nil, _today), do: false

  defp number(%{date: date}), do: date.day
  defp number(nil), do: nil
end
