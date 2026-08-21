defmodule Leaf.Policies.GrantCycle do
  @moduledoc """
  The repeating run of periods an entitlement grants over.

  A cycle is a day of the year and a period length: periods tile the calendar back to back from
  that day, in both directions, so any date falls in exactly one of them. What varies between
  entitlements is only where the run is pinned — someone's start date, their birthday, the
  calendar year, or the organisation's own year.

  Where the pinned day does not exist in a month it is clamped to that month's last day, and every
  period is measured from the pinned day rather than from its predecessor. So a monthly cycle
  pinned to the 31st reaches the 29th in February and the 31st again in March, rather than
  slipping to the 28th for good. The clamped period runs on to meet the next one, leaving no gap.
  """

  @typedoc "What the run of periods is pinned to."
  @type basis :: :employment_date | :birthday | :calendar_year | :organisation_year

  @typedoc "How long each period runs."
  @type period :: :month | :quarter | :year

  @typedoc """
  The dates a cycle can be pinned to.

  Each basis reads exactly one of them, and a missing one it needs is a coding error rather than a
  runtime condition — except `birth_date`, which the organisation genuinely may not hold.
  """
  @type anchors :: %{
          required(:employment_start_date) => Date.t(),
          required(:birth_date) => Date.t() | nil,
          required(:year_start_month) => 1..12
        }

  @type t :: %__MODULE__{anchor_month: 1..12, anchor_day: 1..31, length_months: pos_integer()}

  @enforce_keys [:anchor_month, :anchor_day, :length_months]
  defstruct [:anchor_month, :anchor_day, :length_months]

  @lengths %{month: 1, quarter: 3, year: 12}

  @doc """
  The cycle an entitlement granting `period` on `basis` runs over.

  `:error` only for a birthday cycle where the organisation holds no birth date. Any other missing
  anchor is a coding error and raises.
  """
  @spec new(basis(), period(), anchors()) :: {:ok, t()} | :error
  def new(basis, period, anchors) do
    with {:ok, {month, day}} <- anchor(basis, anchors) do
      {:ok, %__MODULE__{anchor_month: month, anchor_day: day, length_months: @lengths[period]}}
    end
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

  defp anchor(:employment_date, %{employment_start_date: %Date{} = date}),
    do: {:ok, {date.month, date.day}}

  defp anchor(:birthday, %{birth_date: %Date{} = date}), do: {:ok, {date.month, date.day}}
  defp anchor(:birthday, _anchors), do: :error
  defp anchor(:calendar_year, _anchors), do: {:ok, {1, 1}}
  defp anchor(:organisation_year, %{year_start_month: month}), do: {:ok, {month, 1}}

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
