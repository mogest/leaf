defmodule Leaf.Ledger.History do
  @moduledoc """
  One leave type's account over one of the organisation's financial years, a month at a time.

  The year frames what is shown and nothing else: grant periods and anniversaries run as they run.

  Each month's figures are differences of running totals rounded at the month's end, so the columns
  add up to the balances beside them and the last balance is the account's own. The totals nest —
  what was lost, that and what was taken, then the balance — so a column moves only in a month
  something happened in it, and the rounding the balance needs falls to what was earned, the figure
  accrual leaves inexact.

  Leave approved for after the account's `as_at` is booked rather than taken, and nothing is earned
  past `as_at`, so a month holding booked leave ends on the balance with that leave gone.
  """

  alias Leaf.Dates
  alias Leaf.Decimals
  alias Leaf.Ledger.Statement
  alias Leaf.Org.Organisation
  alias Leaf.People.Person

  @typedoc "What a line in a month is: a movement's kind, leave booked ahead, or employment."
  @type kind ::
          Leaf.Ledger.Movement.kind() | :booked | :started | :left

  @typedoc """
  One thing a month holds. Leave is one line for each request, and accrual one for the whole month.

  `days` is how many dates a line of leave covers, and nil on any other line. `column` is the
  figure it counts towards, and nil for a start or an end of employment, which have no `amount`.
  """
  @type line :: %{
          kind: kind(),
          column: :earned | :taken | :lost | nil,
          dates: Date.Range.t(),
          amount: Decimal.t() | nil,
          days: pos_integer() | nil
        }

  @type month :: %{
          dates: Date.Range.t(),
          earned: Decimal.t(),
          taken: Decimal.t(),
          lost: Decimal.t(),
          balance: Decimal.t(),
          booked?: boolean(),
          lines: [line()]
        }

  @typedoc """
  The balance over the year, as dated points to draw lines through.

  `balance` runs to `as_at` and `booked` on from it through the leave booked ahead. A date where
  the balance steps is there twice, before and after, so a line through the points rises with
  accrual and steps with everything else. `as_at` is nil in a year that does not hold it.
  """
  @type chart :: %{
          balance: [{Date.t(), Decimal.t()}],
          booked: [{Date.t(), Decimal.t()}],
          losses: [%{date: Date.t(), kind: kind(), amount: Decimal.t(), balance: Decimal.t()}],
          as_at: Date.t() | nil
        }

  @type t :: %__MODULE__{
          year: integer(),
          dates: Date.Range.t(),
          previous: integer() | nil,
          next: integer() | nil,
          brought_forward: Decimal.t(),
          granted?: boolean(),
          months: [month()],
          chart: chart()
        }

  @enforce_keys [:year, :dates, :previous, :next, :brought_forward, :granted?, :months, :chart]
  defstruct [:year, :dates, :previous, :next, :brought_forward, :granted?, :months, :chart]

  @columns %{
    opening_balance: :earned,
    adjustment: :earned,
    grant: :earned,
    accrual: :earned,
    taken: :taken,
    booked: :taken,
    expiry: :lost,
    rollover_cap: :lost
  }

  @doc """
  The account over the organisation's financial year starting in `year`.

  A nil `year` is the one holding the account's `as_at`. The years run from the first holding
  anything, or the start of the person's tracked employment, to the last holding leave booked or
  `as_at`, and one outside them reads as the nearer end.
  """
  @spec new(Statement.t(), Person.t(), Organisation.t(), integer() | nil) :: t()
  def new(statement, person, organisation, year) do
    %{as_at: as_at} = statement
    %{year_start_month: start_month} = organisation
    events = events(statement)
    tracked = Enum.max([organisation.tracked_from, person.employment_start_date], Date)
    {first, last} = years([tracked, as_at | Enum.map(events, & &1.dates.last)], start_month)
    year = (year || year_of(as_at, start_month)) |> max(first) |> min(last)
    opens = Date.new!(year, start_month, 1)
    dates = Date.range(opens, opens |> Date.shift(year: 1) |> Date.add(-1))
    in_year = Enum.filter(events, &(&1.dates.last in dates))

    %__MODULE__{
      year: year,
      dates: dates,
      previous: within(year - 1, first, last),
      next: within(year + 1, first, last),
      brought_forward: events |> running(Date.add(dates.first, -1)) |> elem(2),
      granted?: granted?(in_year),
      months: months(events, in_year ++ employment(person, dates), dates, as_at),
      chart: chart(events, in_year, dates, as_at)
    }
  end

  defp events(statement) do
    statement.movements
    |> Enum.flat_map(&event(&1, statement.as_at))
    |> Enum.sort_by(& &1.dates.last, Date)
  end

  defp event(%{kind: :accrual} = movement, _as_at) do
    for {dates, amount} <- movement.months, do: event(:accrual, dates, amount)
  end

  defp event(%{kind: :taken} = movement, as_at) do
    kind = if Date.after?(movement.date, as_at), do: :booked, else: :taken
    [%{event(kind, on(movement.date), movement.amount) | request: movement.leave_request_id}]
  end

  defp event(movement, _as_at), do: [event(movement.kind, on(movement.date), movement.amount)]

  defp event(kind, dates, amount), do: %{kind: kind, dates: dates, amount: amount, request: nil}

  defp employment(person, dates) do
    for {kind, date} <- [started: person.employment_start_date, left: person.employment_end_date],
        date != nil and date in dates,
        do: event(kind, on(date), nil)
  end

  defp on(date), do: Date.range(date, date)

  defp years(dates, start_month),
    do: dates |> Enum.map(&year_of(&1, start_month)) |> Enum.min_max()

  defp year_of(date, start_month) when date.month >= start_month, do: date.year
  defp year_of(date, _start_month), do: date.year - 1

  defp within(year, first, last) when year in first..last//1, do: year
  defp within(_year, _first, _last), do: nil

  defp granted?(events) do
    kinds = MapSet.new(events, & &1.kind)

    MapSet.member?(kinds, :grant) and not MapSet.member?(kinds, :accrual)
  end

  # A month is shown where something happened in it, and the month holding `as_at` always is.
  defp months(events, in_year, dates, as_at) do
    for month <- Dates.months(dates),
        lines = lines(Enum.filter(in_year, &(&1.dates.last in month))),
        lines != [] or as_at in month do
      month
      |> figures(events)
      |> Map.merge(%{
        dates: month,
        booked?: Enum.any?(lines, &(&1.kind == :booked)),
        lines: lines
      })
    end
  end

  defp figures(month, events) do
    {lost_before, spent_before, balance_before} = running(events, Date.add(month.first, -1))
    {lost, spent, balance} = running(events, month.last)
    lost_in = Decimal.sub(lost, lost_before)
    spent_in = Decimal.sub(spent, spent_before)

    %{
      earned: balance |> Decimal.sub(balance_before) |> Decimal.sub(spent_in),
      taken: Decimal.sub(spent_in, lost_in),
      lost: lost_in,
      balance: balance
    }
  end

  # What was lost, what was lost or taken, and the balance, to the end of `date`, each rounded.
  defp running(events, date) do
    reached = Enum.reject(events, &Date.after?(&1.dates.last, date))
    lost = for event <- reached, @columns[event.kind] == :lost, do: event.amount
    spent = for event <- reached, @columns[event.kind] != :earned, do: event.amount

    {rounded(lost), rounded(spent), rounded(Enum.map(reached, & &1.amount))}
  end

  defp rounded(amounts), do: amounts |> Decimals.total() |> Decimal.round(2)

  # What the month earned leads, as the one line standing for the whole month.
  defp lines(events) do
    {grouped, single} = Enum.split_with(events, &(&1.kind in [:accrual, :taken, :booked]))

    grouped
    |> Enum.group_by(&{&1.kind, &1.request})
    |> Enum.map(fn {{kind, _request}, events} -> grouped_line(kind, events) end)
    |> Enum.concat(Enum.map(single, &line(&1.kind, &1.dates, &1.amount, nil)))
    |> Enum.sort_by(& &1.dates.first, Date)
    |> Enum.split_with(&(&1.kind == :accrual))
    |> then(fn {earned, rest} -> earned ++ rest end)
  end

  defp grouped_line(kind, events) do
    dates = Enum.flat_map(events, &[&1.dates.first, &1.dates.last])
    amount = Decimals.total(events, & &1.amount)

    line(kind, Dates.spanning(dates), amount, days(kind, events))
  end

  defp days(:accrual, _events), do: nil
  defp days(_kind, events), do: events |> MapSet.new(& &1.dates.first) |> MapSet.size()

  defp line(kind, dates, amount, days) do
    %{kind: kind, column: @columns[kind], dates: dates, amount: amount, days: days}
  end

  defp chart(events, in_year, dates, as_at) do
    opening = balance(events, Date.add(dates.first, -1))
    start = {dates.first, opening}

    {steps, _closing} =
      in_year
      |> Enum.chunk_by(& &1.dates.last)
      |> Enum.flat_map_reduce(opening, &steps/2)

    {held, booked} =
      Enum.split_with(steps, fn {date, _balance} -> not Date.after?(date, as_at) end)

    {balance, booked} = drawn(Date.before?(as_at, dates.first), start, held, booked, dates, as_at)

    %{
      balance: balance,
      booked: booked,
      losses:
        for(
          %{kind: kind, amount: amount, dates: %{last: date}} <- in_year,
          @columns[kind] == :lost,
          do: %{date: date, kind: kind, amount: amount, balance: balance(events, date)}
        ),
      as_at: if(as_at in dates, do: as_at)
    }
  end

  # A year that opens after `as_at` holds nothing but leave booked ahead.
  defp drawn(true, start, _held, booked, _dates, _as_at), do: {[], continued(start, booked)}

  defp drawn(false, start, held, booked, dates, as_at) do
    held = [start | held]
    {_date, balance} = List.last(held)
    reached = {Enum.min([as_at, dates.last], Date), balance}

    {Enum.dedup(held ++ [reached]), continued(reached, booked)}
  end

  defp continued(_from, []), do: []
  defp continued(from, booked), do: Enum.dedup([from | booked])

  defp steps([%{dates: %{last: date}} | _] = day, before) do
    accrued = Decimals.total(for %{kind: :accrual, amount: amount} <- day, do: amount)
    closing = Decimal.add(before, Decimals.total(day, & &1.amount))

    {[{date, Decimal.add(before, accrued)}, {date, closing}], closing}
  end

  defp balance(events, date) do
    events |> Enum.reject(&Date.after?(&1.dates.last, date)) |> Decimals.total(& &1.amount)
  end
end
