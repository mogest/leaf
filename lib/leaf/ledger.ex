defmodule Leaf.Ledger do
  @moduledoc """
  What a person's leave has granted, accrued and lapsed, and what it leaves them holding.

  Nothing here is stored. A balance is worked out from the person's dates, hours, policy and the
  leave they filed, every time it is asked for, so correcting any one of those corrects every
  figure that depended on it and there is nothing left to invalidate.

  A balance comes back as the lots it is made of rather than a single figure, because which lot a
  day off came out of decides what survives, along with the movements that produced it — a figure
  nobody can account for is no use to the person reading it or to payroll.
  """

  alias Leaf.Leave
  alias Leaf.Leave.Day
  alias Leaf.Ledger.Drawdown
  alias Leaf.Ledger.Grant
  alias Leaf.Ledger.Movement
  alias Leaf.Ledger.Span
  alias Leaf.Ledger.Statement
  alias Leaf.Org
  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.Policies

  @doc """
  An account for each leave type the person holds one in, as at `as_at`, in the organisation's
  order.

  A leave type appears where the person holds a balance in it — something granted to them, entered
  by hand, or filed against it. A type that grants nothing and is recorded only appears once there
  is leave against it, so what somebody *may* request comes from their policy, not from here.

  `days` are leave to count alongside what has been filed, which is what answers what a balance
  would be were a request approved. Where they run past `as_at` the account runs on to the last of
  them, since a balance that stopped short of the leave being asked about would not answer the
  question. What is already filed stays counted either way, so projecting an *amendment* means
  leaving that request's own days out of `days`.
  """
  @spec statements(Person.t(), Date.t(), [Day.t()]) :: [Statement.t()]
  def statements(person, as_at, days \\ []) do
    as_at = Enum.reduce(days, as_at, &Enum.max([&1.date, &2], Date))
    {:ok, organisation} = Org.fetch_organisation(person.organisation_id)
    spans = Span.all(person, organisation, as_at)
    leave_types = Policies.leave_types(organisation.id)
    taken = Leave.days_taken(person, as_at) ++ days

    context = %{
      organisation: organisation,
      as_at: as_at,
      holidays: observed_holidays(person, spans),
      spans: spans,
      entered: Leave.balance_entries(person, as_at),
      taken: taken,
      hours: hours_taken_against(person, taken, leave_types)
    }

    Enum.flat_map(leave_types, &statement(&1, context))
  end

  @doc """
  The person's account in one leave type, or `:error` where they hold none.

  Every leave type replays from the date the organisation started tracking leave, so this works
  the whole ledger out and takes one account from it: one type on its own is no less work.
  """
  @spec fetch_statement(Person.t(), Ecto.UUID.t(), Date.t(), [Day.t()]) ::
          {:ok, Statement.t()} | :error
  def fetch_statement(person, leave_type_id, as_at, days \\ []) do
    case Enum.find(statements(person, as_at, days), &(&1.leave_type.id == leave_type_id)) do
      nil -> :error
      statement -> {:ok, statement}
    end
  end

  defp statement(leave_type, context) do
    spans = Enum.filter(context.spans, &(&1.entitlement.leave_type_id == leave_type.id))
    entered = of_type(context.entered, leave_type)
    taken = of_type(context.taken, leave_type)

    case {spans, entered, taken} do
      {[], [], []} -> []
      _held -> [replay(leave_type, context, spans, entered, taken)]
    end
  end

  defp of_type(rows, leave_type), do: Enum.filter(rows, &(&1.leave_type_id == leave_type.id))

  defp replay(leave_type, context, spans, entered, taken) do
    movements =
      Enum.flat_map(spans, &Grant.movements(&1, context.organisation, context.holidays)) ++
        Enum.map(entered, &entered_movement/1) ++
        Enum.map(taken, &taken_movement(&1, leave_type, context.hours))

    {movements, lots} = Drawdown.run(movements, Grant.caps(spans), context.as_at)

    Statement.new(leave_type, movements, lots)
  end

  defp entered_movement(entry) do
    %Movement{
      date: entry.date,
      kind: entry.kind,
      amount: entry.amount,
      expires_on: entry.expires_on
    }
  end

  defp taken_movement(day, leave_type, hours) do
    amount = Day.in_unit(day, leave_type.unit, hours[day.date])

    %Movement{date: day.date, kind: :taken, amount: Decimal.negate(amount)}
  end

  # A day asked for in the unit its leave type counts in converts through nothing, and most are,
  # so the work patterns are read only where one is not. A day older than the person's pattern
  # history still counts for as much as it says, so long as nobody has to say how long it was.
  defp hours_taken_against(person, taken, leave_types) do
    units = Map.new(leave_types, &{&1.id, &1.unit})

    case Enum.reject(taken, &(&1.unit == Map.fetch!(units, &1.leave_type_id))) do
      [] -> %{}
      converting -> person |> People.hours_per_day(dates_spanned(converting)) |> Map.new()
    end
  end

  defp dates_spanned(days) do
    dates = Enum.map(days, & &1.date)

    Date.range(Enum.min(dates, Date), Enum.max(dates, Date))
  end

  # A public holiday allowance is counted over the whole grant period it belongs to, which can run
  # past the date being asked about, so the calendar is read over the periods rather than the
  # range. Nothing else needs it, so nothing else pays for reading it.
  defp observed_holidays(person, spans) do
    case Enum.filter(spans, &(&1.entitlement.amount_source == :public_holidays)) do
      [] -> []
      counted -> holidays(person, periods_spanned(counted))
    end
  end

  defp periods_spanned(spans) do
    Date.range(
      spans |> Enum.map(& &1.period.first) |> Enum.min(Date),
      spans |> Enum.map(& &1.period.last) |> Enum.max(Date)
    )
  end

  # The count claims to be the period's whole share of the calendar, so a period the person
  # observes no calendar over part of would be quietly short of one.
  defp holidays(person, range) do
    person
    |> People.holiday_calendar_segments!(range)
    |> Enum.flat_map(fn {span, calendar_id} -> Org.public_holidays(calendar_id, span) end)
    |> Enum.map(& &1.date)
  end
end
