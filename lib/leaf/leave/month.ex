defmodule Leaf.Leave.Month do
  @moduledoc """
  A month of somebody's leave, as the weeks it is really made of.

  A day carries what the person needs to see of it: whether they work it, what became of any leave
  they hold on it, and which public holiday it is. A cell outside the month is `nil`, so a week is
  always seven cells and every column stands under its own weekday.
  """

  alias Leaf.Leave.Day
  alias Leaf.Leave.WorkingDay
  alias Leaf.People
  alias Leaf.People.Person

  @typedoc "One date, and what is on it."
  @type day :: %{
          date: Date.t(),
          working?: boolean(),
          leave: :approved | :pending | nil,
          holiday: String.t() | nil
        }

  @type t :: %__MODULE__{starts_on: Date.t(), weeks: [[day() | nil]]}

  @enforce_keys [:starts_on, :weeks]
  defstruct [:starts_on, :weeks]

  @none Decimal.new(0)

  @doc """
  A month for each one `range` runs over, marked with `filed` and with the person's own dates.

  A date they are on no work pattern for is one they do not work: nobody may book it either way,
  and a calendar has nothing to say about why.
  """
  @spec over(Person.t(), Date.Range.t(), [Day.t()]) :: [t()]
  def over(person, range, filed) do
    marks = %{
      hours: person |> WorkingDay.hours_per_day(range) |> Map.new(),
      holidays: person |> People.public_holidays(range) |> Map.new(&{&1.date, &1.name}),
      filed: filed_by_date(filed)
    }

    range |> Enum.map(&day(&1, marks)) |> Enum.chunk_by(& &1.date.month) |> Enum.map(&month/1)
  end

  # A date can hold leave of more than one type, and of more than one request. What shows is the
  # furthest along: an approved day is settled whatever else has been asked for on it.
  defp filed_by_date(days) do
    days
    |> Enum.group_by(& &1.date, & &1.leave_request.status)
    |> Map.new(fn {date, statuses} -> {date, settled(:approved in statuses)} end)
  end

  defp settled(true), do: :approved
  defp settled(false), do: :pending

  defp day(date, marks) do
    %{
      date: date,
      working?: Decimal.positive?(Map.get(marks.hours, date, @none)),
      leave: marks.filed[date],
      holiday: marks.holidays[date]
    }
  end

  defp month([first | _rest] = days) do
    %__MODULE__{starts_on: Date.beginning_of_month(first.date), weeks: weeks(days)}
  end

  defp weeks([first | _rest] = days) do
    Enum.chunk_every(before(first) ++ days, 7, 7, List.duplicate(nil, 6))
  end

  defp before(first), do: List.duplicate(nil, Date.day_of_week(first.date) - 1)
end
