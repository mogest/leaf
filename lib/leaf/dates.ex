defmodule Leaf.Dates do
  @moduledoc "Date helpers shared across areas."

  @doc "The narrowest range covering every one of `dates`."
  @spec spanning([Date.t()]) :: Date.Range.t()
  def spanning(dates), do: Date.range(Enum.min(dates, Date), Enum.max(dates, Date))

  @doc """
  The earlier of two dates, where `nil` is no bound at all and so the other date wins.

  Two `nil`s are `nil`.
  """
  @spec earliest(Date.t() | nil, Date.t() | nil) :: Date.t() | nil
  def earliest(nil, date), do: date
  def earliest(date, nil), do: date
  def earliest(a, b), do: Enum.min([a, b], Date)

  @doc """
  The part of `range` from `from` to `to`, where a `to` of `nil` is no bound at all.

  `:error` where they leave nothing.
  """
  @spec intersect(Date.Range.t(), Date.t(), Date.t() | nil) :: {:ok, Date.Range.t()} | :error
  def intersect(range, from, to) do
    bounded(Enum.max([range.first, from], Date), earliest(range.last, to))
  end

  @doc "`range` cut at the end of every month it runs through."
  @spec months(Date.Range.t()) :: [Date.Range.t()]
  def months(range) do
    range.first
    |> Date.beginning_of_month()
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&(not Date.after?(&1, range.last)))
    |> Enum.map(fn month ->
      {:ok, part} = intersect(range, month, Date.end_of_month(month))
      part
    end)
  end

  @doc "The year starting in `start_month` that holds `date`, named for the calendar year it starts in."
  @spec year_of(Date.t(), 1..12) :: integer()
  def year_of(date, start_month) when date.month >= start_month, do: date.year
  def year_of(date, _start_month), do: date.year - 1

  @doc "The dates of the year starting in `start_month` of `year`."
  @spec year(integer(), 1..12) :: Date.Range.t()
  def year(year, start_month) do
    first = Date.new!(year, start_month, 1)

    Date.range(first, first |> Date.shift(year: 1) |> Date.add(-1))
  end

  @doc "The instant `date` begins in `zone`."
  @spec midnight(Date.t(), String.t()) :: DateTime.t()
  def midnight(date, zone) do
    # A zone that moves its clocks at midnight has a day with no midnight, or with two.
    case DateTime.new(date, ~T[00:00:00], zone) do
      {:ok, at} -> at
      {:gap, _before, starts} -> starts
      {:ambiguous, first, _second} -> first
    end
  end

  @doc "The range from `first` to `last`, or `:error` where `last` is before `first`."
  @spec bounded(Date.t(), Date.t()) :: {:ok, Date.Range.t()} | :error
  def bounded(first, last) do
    case Date.compare(first, last) do
      :gt -> :error
      _ -> {:ok, Date.range(first, last)}
    end
  end
end
