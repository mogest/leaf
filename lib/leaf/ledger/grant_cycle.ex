defmodule Leaf.Ledger.GrantCycle do
  @moduledoc """
  The repeating run of periods an entitlement grants over.

  A cycle is a day of the year and a period length: periods tile the calendar back to back from
  that day, in both directions, so any date falls in exactly one of them. What varies between
  entitlements is only where the run is pinned and how long each period runs; which of a person's
  or an organisation's dates does the pinning is the caller's business, not this module's.

  Where the pinned day does not exist in a month it is clamped to that month's last day, and every
  period is measured from the pinned day rather than from its predecessor. So a monthly cycle
  pinned to the 31st reaches the 29th in February and the 31st again in March, rather than
  slipping to the 28th for good. The clamped period runs on to meet the next one, leaving no gap.
  """

  @typedoc "How long each period runs."
  @type period :: :month | :quarter | :year

  @type t :: %__MODULE__{anchor_month: 1..12, anchor_day: 1..31, length_months: pos_integer()}

  @enforce_keys [:anchor_month, :anchor_day, :length_months]
  defstruct [:anchor_month, :anchor_day, :length_months]

  @lengths %{month: 1, quarter: 3, year: 12}

  @doc "The cycle whose periods run `period` at a time, pinned to a day of the year."
  @spec new(1..12, 1..31, period()) :: t()
  def new(anchor_month, anchor_day, period) do
    %__MODULE__{
      anchor_month: anchor_month,
      anchor_day: anchor_day,
      length_months: @lengths[period]
    }
  end

  @doc "The period `date` falls in."
  @spec period_containing(t(), Date.t()) :: Date.Range.t()
  def period_containing(cycle, date) do
    locate(cycle, date, Integer.floor_div(date.month - cycle.anchor_month, cycle.length_months))
  end

  @doc "Every period overlapping `range`, in order."
  @spec periods_overlapping(t(), Date.Range.t()) :: [Date.Range.t()]
  def periods_overlapping(cycle, range) do
    cycle
    |> period_containing(range.first)
    |> Stream.iterate(&period_containing(cycle, Date.add(&1.last, 1)))
    |> Enum.take_while(&(not Date.after?(&1.first, range.last)))
  end

  # The initial index lands on the right period or one either side of it, because a period's own
  # bounds depend on the anchor day, which the month arithmetic that produced the index ignores.
  defp locate(cycle, date, index) do
    first = starts_on(cycle, date.year, index)
    last = Date.add(starts_on(cycle, date.year, index + 1), -1)

    cond do
      Date.before?(date, first) -> locate(cycle, date, index - 1)
      Date.after?(date, last) -> locate(cycle, date, index + 1)
      true -> Date.range(first, last)
    end
  end

  defp starts_on(cycle, year, index) do
    month = Date.shift(Date.new!(year, cycle.anchor_month, 1), month: index * cycle.length_months)

    Date.new!(month.year, month.month, min(cycle.anchor_day, Date.days_in_month(month)))
  end
end
