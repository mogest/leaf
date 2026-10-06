defmodule Leaf.Leave.Diary do
  @moduledoc """
  Each date in a range, and what is on it for one person.

  Whether they work it, what became of any leave they hold on it, and which public holiday it is,
  all read off the same dates. A month grid and a row in a who-is-away chart want the same days,
  so this is where a day is decided and neither of them decides it again.
  """

  alias Leaf.Leave.Day
  alias Leaf.Leave.WorkingDay
  alias Leaf.People
  alias Leaf.People.Person

  @typedoc """
  One date, and what is on it.

  `part?` is whether the leave shown covers less than the hours the day is worked.
  """
  @type day :: %{
          date: Date.t(),
          working?: boolean(),
          leave: :approved | :pending | nil,
          part?: boolean(),
          holiday: String.t() | nil
        }

  @none Decimal.new(0)

  @doc """
  Every date in `range`, in order, marked with `filed` and with the person's own dates.

  A date they are on no work pattern for is one they do not work: nobody may book it either way,
  and a calendar has nothing to say about why.
  """
  @spec over(Person.t(), Date.Range.t(), [Day.t()]) :: [day()]
  def over(person, range, filed) do
    marks = %{
      hours: person |> WorkingDay.hours_per_day(range) |> Map.new(),
      holidays: person |> People.public_holidays(range) |> Map.new(&{&1.date, &1.name}),
      filed: Enum.group_by(filed, & &1.date)
    }

    Enum.map(range, &day(&1, marks))
  end

  defp day(date, marks) do
    hours = Map.get(marks.hours, date, @none)
    {leave, part?} = leave(Map.get(marks.filed, date, []), hours)

    %{
      date: date,
      working?: Decimal.positive?(hours),
      leave: leave,
      part?: part?,
      holiday: marks.holidays[date]
    }
  end

  defp leave([], _hours), do: {nil, false}

  defp leave(days, hours) do
    {status, shown} = days |> Enum.group_by(& &1.leave_request.status) |> furthest()
    taken = Enum.reduce(shown, @none, &Decimal.add(&2, Day.in_unit(&1, :hours, hours)))

    {status, Decimal.lt?(taken, hours)}
  end

  # A date can hold leave of more than one type, and of more than one request. What shows is the
  # furthest along: an approved day is settled whatever else has been asked for on it.
  defp furthest(%{approved: days}), do: {:approved, days}
  defp furthest(%{pending: days}), do: {:pending, days}
end
