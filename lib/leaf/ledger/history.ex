defmodule Leaf.Ledger.History do
  @moduledoc """
  One leave type's account over one of the organisation's financial years, a month at a time.

  The year frames what is shown and nothing else: grant periods and anniversaries run as they run.

  Every figure shown is a difference of the running balance rounded: each line is what it moves
  the rounded balance by, read in the order the lines are listed, and a month's column is the sum
  of its lines. So lines add up to their month, months to the balances beside them, a column only
  moves where something of its kind happened, and the last balance is the account's own.

  Leave approved for after the account's `as_at` is booked rather than taken, and nothing is earned
  past `as_at`, so a month holding booked leave ends on the balance with that leave gone.
  """

  alias Leaf.Dates
  alias Leaf.Decimals
  alias Leaf.Ledger.Span
  alias Leaf.Ledger.Statement
  alias Leaf.People.Person

  @typedoc "What a line in a month is: a movement's kind, leave booked ahead, or employment."
  @type kind ::
          Leaf.Ledger.Movement.kind() | :booked | :started | :left

  @typedoc """
  One thing a month holds: a line for each request of leave, and one for the whole month's accrual.

  `days` is how many dates a line of leave drew on, and nil on any other line. `column` is the
  figure it counts towards, and nil for a start or an end of employment, which have no `amount`.
  `amount` is as shown, already rounded.
  """
  @type line :: %{
          kind: kind(),
          column: :earned | :taken | :lost | nil,
          dates: Date.Range.t(),
          amount: Decimal.t() | nil,
          days: non_neg_integer() | nil
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
  accrual and steps with everything else. A loss is drawn `at` the end of its `date`, which is
  the next day. `as_at` is nil in a year that does not hold it.
  """
  @type chart :: %{
          balance: [{Date.t(), Decimal.t()}],
          booked: [{Date.t(), Decimal.t()}],
          losses: [
            %{
              date: Date.t(),
              at: Date.t(),
              kind: kind(),
              amount: Decimal.t(),
              balance: Decimal.t()
            }
          ],
          as_at: Date.t() | nil
        }

  @type t :: %__MODULE__{
          year: integer(),
          dates: Date.Range.t(),
          previous: integer() | nil,
          next: integer() | nil,
          brought_forward: Decimal.t(),
          brought_in: Date.t() | nil,
          granted?: boolean(),
          months: [month()],
          chart: chart()
        }

  @enforce_keys [
    :year,
    :dates,
    :previous,
    :next,
    :brought_forward,
    :brought_in,
    :granted?,
    :months,
    :chart
  ]
  defstruct @enforce_keys

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

  @figures [:earned, :taken, :lost]

  @doc """
  The account over the organisation's financial year starting in `year`.

  `person` carries their organisation. A nil `year` is the one holding the account's `as_at`. The
  years run from the first holding anything, or the start of the person's tracked employment, to
  the last holding anything, or the end of that employment where it ended before `as_at`, and one
  outside them reads as the nearer end.

  An opening balance dated where the ledger starts is what the person held before it, so it is
  brought forward into the first year. `brought_in` is where the ledger starts, in the year it does.

  `granted?` is whether the type is granted whole at a period's start rather than earned as it
  goes, by `timings`, the grant timing of each entitlement the person holds in it.
  """
  @spec new(Statement.t(), Person.t(), [:daily | :period_start], integer() | nil) :: t()
  def new(statement, person, timings, year) do
    %{as_at: as_at} = statement
    %{organisation: organisation} = person
    %{year_start_month: start_month} = organisation
    [starts | _] = tracked = tracked(person, organisation, as_at)
    %{first: opens} = starts |> Dates.year_of(start_month) |> Dates.year(start_month)
    eve = Date.add(opens, -1)
    events = events(statement, starts, eve)
    moved = for %{dates: dates} <- events, dates.last != eve, do: dates.last
    {first, last} = years(tracked ++ moved, start_month)
    year = (year || Dates.year_of(as_at, start_month)) |> max(first) |> min(last)
    dates = Dates.year(year, start_month)
    months = Dates.months(dates)
    totals = totals(events, [Date.add(dates.first, -1) | Enum.map(months, & &1.last)])
    in_year = Enum.filter(events, &(&1.dates.last in dates))

    %__MODULE__{
      year: year,
      dates: dates,
      previous: within(year - 1, first, last),
      next: within(year + 1, first, last),
      brought_forward: Decimal.round(hd(totals), 2),
      brought_in: if(starts in dates, do: starts),
      granted?: Enum.uniq(timings) == [:period_start],
      months: months(months, totals, in_year ++ employment(person, dates), as_at),
      chart: chart(events, dates, as_at)
    }
  end

  defp tracked(person, organisation, as_at) do
    case Span.tracked_range(person, organisation, as_at) do
      {:ok, range} -> [range.first, range.last]
      :error -> [as_at]
    end
  end

  # Only an opening balance from where the ledger starts is what the person brought into it; one
  # entered later is a figure like any other, on its own date.
  defp brought?(%{kind: kind, date: date}, starts),
    do: kind == :opening_balance and not Date.after?(date, starts)

  defp events(statement, starts, eve) do
    statement.movements
    |> Enum.flat_map(&events_of(&1, statement.as_at, starts, eve))
    |> Enum.reject(&Decimal.equal?(&1.amount, 0))
    |> Enum.sort_by(& &1.dates.last, Date)
  end

  defp events_of(%{kind: :accrual} = movement, _as_at, _starts, _eve) do
    for {dates, amount} <- movement.months, do: event(:accrual, dates, amount)
  end

  defp events_of(%{kind: :taken} = movement, as_at, _starts, _eve) do
    kind = if Date.after?(movement.date, as_at), do: :booked, else: :taken
    [%{event(kind, on(movement.date), movement.amount) | request: movement.leave_request_id}]
  end

  # Brought in, it is dated the eve of the first year, so it is what that year opens on.
  defp events_of(movement, _as_at, starts, eve) do
    date = if brought?(movement, starts), do: eve, else: movement.date

    [event(movement.kind, on(date), movement.amount)]
  end

  defp event(kind, dates, amount), do: %{kind: kind, dates: dates, amount: amount, request: nil}

  defp employment(person, dates) do
    for {kind, date} <- [started: person.employment_start_date, left: person.employment_end_date],
        date != nil and date in dates,
        do: event(kind, on(date), nil)
  end

  defp on(date), do: Date.range(date, date)

  defp years(dates, start_month),
    do: dates |> Enum.map(&Dates.year_of(&1, start_month)) |> Enum.min_max()

  defp within(year, first, last) when year in first..last//1, do: year
  defp within(_year, _first, _last), do: nil

  # The exact balance at the end of each of `ends`, in one pass.
  defp totals(events, ends) do
    {totals, _left} =
      Enum.map_reduce(ends, {Decimal.new(0), events}, fn date, {total, events} ->
        {reached, left} = Enum.split_while(events, &(not Date.after?(&1.dates.last, date)))
        total = Decimal.add(total, Decimals.total(reached, & &1.amount))

        {total, {total, left}}
      end)

    totals
  end

  # A month is shown where something happened in it, and the month holding `as_at` always is.
  defp months(months, totals, in_year, as_at) do
    for {month, before, total} <- Enum.zip([months, totals, tl(totals)]),
        lines = lines(Enum.filter(in_year, &(&1.dates.last in month)), before),
        lines != [] or as_at in month do
      @figures
      |> Map.new(&{&1, column(lines, &1)})
      |> Map.merge(%{
        dates: month,
        balance: Decimal.round(total, 2),
        booked?: Enum.any?(lines, &(&1.kind == :booked)),
        lines: lines
      })
    end
  end

  defp column(lines, figure) do
    amounts = for %{column: ^figure, amount: amount} <- lines, do: amount

    amounts |> Decimals.total() |> Decimal.round(2)
  end

  defp lines(events, before) do
    {grouped, single} = Enum.split_with(events, &(&1.kind in [:accrual, :taken, :booked]))

    {lines, _total} =
      grouped
      |> Enum.group_by(&{&1.kind, &1.request})
      |> Enum.map(fn {{kind, _request}, events} -> grouped_line(kind, events) end)
      |> Enum.concat(Enum.map(single, &line(&1.kind, &1.dates, &1.amount, nil)))
      |> Enum.sort_by(& &1.dates.first, Date)
      |> Enum.split_with(&(&1.kind == :accrual))
      |> then(fn {earned, rest} -> earned ++ rest end)
      |> Enum.map_reduce(before, &shown/2)

    lines
  end

  defp shown(%{amount: nil} = line, total), do: {line, total}

  defp shown(line, total) do
    reached = Decimal.add(total, line.amount)

    {%{line | amount: Decimal.sub(Decimal.round(reached, 2), Decimal.round(total, 2))}, reached}
  end

  defp grouped_line(kind, events) do
    dates = Enum.flat_map(events, &[&1.dates.first, &1.dates.last])
    amount = Decimals.total(events, & &1.amount)

    line(kind, Dates.spanning(dates), amount, days(kind, events))
  end

  defp days(:accrual, _events), do: nil

  defp days(_kind, events), do: events |> Enum.uniq_by(& &1.dates.first) |> length()

  defp line(kind, dates, amount, days) do
    %{kind: kind, column: @columns[kind], dates: dates, amount: amount, days: days}
  end

  defp chart(events, dates, as_at) do
    events = Enum.map(events, &Map.put(&1, :at, at(&1, dates, as_at)))
    opening = balance(events, Date.add(dates.first, -1))
    in_year = events |> Enum.filter(&(&1.at in dates)) |> Enum.sort_by(& &1.at, Date)

    {steps, _closing} =
      in_year
      |> Enum.chunk_by(& &1.at)
      |> Enum.flat_map_reduce(opening, &steps/2)

    {held, ahead} =
      Enum.split_with([{dates.first, opening} | steps], fn {date, _balance} ->
        not Date.after?(date, as_at)
      end)

    balance = held(held, Enum.min([as_at, dates.last], Date))

    %{
      balance: balance,
      booked: booked(Enum.take(balance, -1) ++ ahead),
      losses:
        for(
          %{kind: kind, amount: amount, dates: %{last: date}, at: at} <- in_year,
          @columns[kind] == :lost,
          do: %{date: date, at: at, kind: kind, amount: amount, balance: balance(events, at)}
        ),
      as_at: if(as_at in dates, do: as_at)
    }
  end

  # What lapses on a date is gone once the day is over, which is the moment the next day's grant
  # arrives, so the two are drawn as one step rather than a dip to nothing between them. On `as_at`
  # it stays put, being part of the balance as at that day, and on the year's last day, being part
  # of how the year ends.
  defp at(%{kind: kind, dates: %{last: date}}, dates, as_at) do
    if @columns[kind] == :lost and date in dates and date != dates.last and
         Date.before?(date, as_at),
       do: Date.add(date, 1),
       else: date
  end

  # A year that opens after `as_at` holds nothing but leave booked ahead.
  defp held([], _reached), do: []

  defp held(held, reached) do
    {_date, balance} = List.last(held)

    Enum.dedup(held ++ [{reached, balance}])
  end

  defp booked([_from]), do: []
  defp booked(points), do: Enum.dedup(points)

  defp steps([%{at: date} | _] = day, before) do
    accrued = Decimals.total(for %{kind: :accrual, amount: amount} <- day, do: amount)
    closing = Decimal.add(before, Decimals.total(day, & &1.amount))

    {[{date, Decimal.add(before, accrued)}, {date, closing}], closing}
  end

  defp balance(events, date) do
    events |> Enum.reject(&Date.after?(&1.at, date)) |> Decimals.total(& &1.amount)
  end
end
