defmodule Leaf.Leave.WorkingDay do
  @moduledoc """
  The hours a person works on each date, a public holiday they are granted off counting as none.

  A public holiday is an ordinary working day for somebody exactly when their policy credits them
  its share of the calendar instead (§4.9). Everybody else simply does not work it: no leave is
  deducted for it, and a multi-day request steps over it rather than spending a day on it.

  A date the person is on no work pattern for is absent rather than none, as it is in
  `Leaf.People.hours_per_day/2`, so that a caller can tell a day off from a hole in the record.
  """

  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.Policies

  @none Decimal.new(0)

  @doc "The hours the person works on each date in `range` they are on a pattern for, in order."
  @spec hours_per_day(Person.t(), Date.Range.t()) :: [{Date.t(), Decimal.t()}]
  def hours_per_day(person, range) do
    person |> People.hours_per_day(range) |> less_granted_off(person, range)
  end

  @doc "The same, refusing a `range` the person has no work pattern over part of."
  @spec hours_per_day!(Person.t(), Date.Range.t()) :: [{Date.t(), Decimal.t()}]
  def hours_per_day!(person, range) do
    person |> People.hours_per_day!(range) |> less_granted_off(person, range)
  end

  defp less_granted_off(hours_per_day, person, range) do
    off = granted_off(person, range)

    Enum.map(hours_per_day, fn {date, hours} -> {date, worked(date, hours, off)} end)
  end

  defp worked(date, hours, off) do
    case MapSet.member?(off, date) do
      true -> @none
      false -> hours
    end
  end

  # Most ranges hold no public holiday at all, and nothing else here needs the policy, so a range
  # that holds none does not pay for reading one.
  defp granted_off(person, range) do
    person |> observed(range) |> less_credited(person, range)
  end

  defp less_credited([], _person, _range), do: MapSet.new()

  defp less_credited(dates, person, range) do
    credited = Policies.crediting(person, range)

    dates |> Enum.reject(fn date -> Enum.any?(credited, &(date in &1)) end) |> MapSet.new()
  end

  defp observed(person, range) do
    person |> People.public_holidays(range) |> Enum.map(& &1.date)
  end
end
