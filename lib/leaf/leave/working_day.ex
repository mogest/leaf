defmodule Leaf.Leave.WorkingDay do
  @moduledoc """
  The hours a person works on each date, a public holiday they are granted off counting as none.

  A public holiday is an ordinary working day for somebody exactly when their policy credits them
  its share of the calendar instead (§4.9). Everybody else simply does not work it: no leave is
  deducted for it, and a multi-day request steps over it rather than spending a day on it.

  A date the person is on no work pattern for is absent rather than none, as it is in
  `Leaf.People.hours_per_day/2`, so that a caller can tell a day off from a hole in the record.
  """

  alias Leaf.Org
  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.Policies

  @none Decimal.new(0)

  @doc "The hours the person works on each date in `range` they are on a pattern for, in order."
  @spec hours_per_day(Person.t(), Date.Range.t()) :: [{Date.t(), Decimal.t()}]
  def hours_per_day(person, range) do
    off = granted_off(person, range)

    person
    |> People.hours_per_day(range)
    |> Enum.map(fn {date, hours} -> {date, worked(date, hours, off)} end)
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
    credited = credited(person, range)

    dates |> Enum.reject(fn date -> Enum.any?(credited, &(date in &1)) end) |> MapSet.new()
  end

  defp observed(person, range) do
    person
    |> People.holiday_calendar_segments(range)
    |> Enum.flat_map(fn {span, calendar_id} -> Org.public_holidays(calendar_id, span) end)
    |> Enum.map(& &1.date)
  end

  # The stretches of `range` over which the person's policy credits public holidays rather than
  # granting them off.
  defp credited(person, range) do
    person
    |> People.leave_policy_segments(range)
    |> Enum.flat_map(fn {span, policy_id} -> crediting(policy_id, span) end)
  end

  defp crediting(policy_id, span) do
    policy_id
    |> Policies.entitlements(span)
    |> Enum.filter(&(&1.amount_source == :public_holidays))
    |> Enum.map(&Date.range(Enum.max([&1.effective_from, span.first], Date), closes_on(&1, span)))
  end

  defp closes_on(%{effective_to: nil}, span), do: span.last
  defp closes_on(entitlement, span), do: Enum.min([entitlement.effective_to, span.last], Date)
end
