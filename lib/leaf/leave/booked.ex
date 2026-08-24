defmodule Leaf.Leave.Booked do
  @moduledoc """
  The leave a person's dates already hold, and whether more of a day is left to file.

  A day holds the hours the person works on it and no more, however many leave types share it: 7.2
  hours of quarterly leave and 1.8 of annual make up one nine-hour day, and a whole day filed over
  the top of that is not leave anybody can take. Leave somebody is waiting on holds the day as
  firmly as leave they hold — a request nobody has decided is one they are counting on, and two of
  them over the same hours is a pair nobody can approve. Declined and cancelled leave holds nothing.

  A request being amended does not clash with itself. What it asks for now replaces what it asked
  for, so its own days come off the day before the rest are counted.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Leaf.Dates
  alias Leaf.Leave.Day
  alias Leaf.Leave.Request
  alias Leaf.Leave.WorkingDay
  alias Leaf.People.Person
  alias Leaf.Repo

  @none Decimal.new(0)

  @doc """
  Every day of leave a person still holds within `range`, oldest first, with its request.

  Approved and pending only. A declined day was never leave and a cancelled one has stopped being
  it, so neither holds its date; a pending one does, because the person is counting on it.
  """
  @spec days(Person.t(), Date.Range.t()) :: [Day.t()]
  def days(person, range) do
    Repo.all(
      from [day, request] in held(person, range),
        order_by: day.date,
        preload: [leave_request: request]
    )
  end

  @doc "Whether the person holds any leave of that type within `range`, by the same rule."
  @spec any?(Person.t(), Ecto.UUID.t(), Date.Range.t()) :: boolean()
  def any?(person, leave_type_id, range) do
    Repo.exists?(from day in held(person, range), where: day.leave_type_id == ^leave_type_id)
  end

  defp held(person, range) do
    from day in Day,
      join: request in assoc(day, :leave_request),
      where: request.person_id == ^person.id,
      where: request.status in [:approved, :pending],
      where: day.date >= ^range.first and day.date <= ^range.last
  end

  @doc """
  The dates `filing` asks more of than is left, oldest first, each with the hours it has free.

  `except` is the request the days are replacing, whose own days are set aside. Everything is
  counted in hours, whatever unit it was asked in, because hours are what a day holds.
  """
  @spec clashing(Person.t(), [Day.t()], Ecto.UUID.t() | nil) :: [{Date.t(), Decimal.t()}]
  def clashing(_person, [], _except), do: []

  def clashing(person, filing, except) do
    span = Dates.spanning(Enum.map(filing, & &1.date))
    hours = person |> WorkingDay.hours_per_day(span) |> Map.new()
    free = person |> days(span) |> Enum.reject(&(&1.leave_request_id == except)) |> unspent(hours)

    filing
    |> tally(hours)
    |> Enum.filter(fn {date, asked} -> Decimal.gt?(asked, at(free, date)) end)
    |> Enum.map(fn {date, _asked} -> {date, at(free, date)} end)
    |> Enum.sort_by(&elem(&1, 0), Date)
  end

  @doc """
  Errors on a request asking for more of a date than is left in it.

  A request's days are one thing asked for and one thing refused, so the refusal is about all of
  them: which dates clash is `clashing/3`'s to say, and a form filling a request in says it before
  there is anything to refuse. Days already refused for themselves are left as they are — a date
  nobody works has no hours to have run out of.
  """
  @spec validate(Changeset.t(), Person.t()) :: Changeset.t()
  def validate(%{valid?: false} = changeset, _person), do: changeset

  def validate(changeset, person) do
    fits(changeset, clashing(person, Request.filing(changeset), changeset.data.id))
  end

  defp fits(changeset, []), do: changeset

  defp fits(changeset, [_clash | _rest]) do
    Changeset.add_error(changeset, :days, "ask for more of a day than is left in it")
  end

  defp unspent(booked, hours) do
    spent = tally(booked, hours)

    Map.new(hours, fn {date, worked} -> {date, Decimal.sub(worked, at(spent, date))} end)
  end

  defp tally(days, hours) do
    days
    |> Enum.group_by(& &1.date)
    |> Map.new(fn {date, on_date} -> {date, summed(on_date, at(hours, date))} end)
  end

  defp summed(days, hours) do
    Enum.reduce(days, @none, &Decimal.add(&2, Day.in_unit(&1, :hours, hours)))
  end

  # A date the person is on no pattern for has no hours to spend, which is the same answer as none
  # left: leave filed into a hole in the record is refused for being in one.
  defp at(hours, date), do: Map.get(hours, date, @none)
end
