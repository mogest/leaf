defmodule Leaf.Leave.Month do
  @moduledoc """
  A month of somebody's leave, as the weeks it is really made of.

  What each day carries is `Leaf.Leave.Diary`'s to say. This lays those days out: a cell outside
  the month is `nil`, so a week is always seven cells and every column stands under its own
  weekday.
  """

  alias Leaf.Leave.Day
  alias Leaf.Leave.Diary
  alias Leaf.People.Person

  @type t :: %__MODULE__{starts_on: Date.t(), weeks: [[Diary.day() | nil]]}

  @enforce_keys [:starts_on, :weeks]
  defstruct [:starts_on, :weeks]

  @doc "A month for each one `range` runs over, marked with `filed` and the person's own dates."
  @spec over(Person.t(), Date.Range.t(), [Day.t()]) :: [t()]
  def over(person, range, filed) do
    person
    |> Diary.over(range, filed)
    |> Enum.chunk_by(& &1.date.month)
    |> Enum.map(&month/1)
  end

  defp month([first | _rest] = days) do
    %__MODULE__{starts_on: Date.beginning_of_month(first.date), weeks: weeks(days)}
  end

  defp weeks([first | _rest] = days) do
    Enum.chunk_every(before(first) ++ days, 7, 7, List.duplicate(nil, 6))
  end

  defp before(first), do: List.duplicate(nil, Date.day_of_week(first.date) - 1)
end
