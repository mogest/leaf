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

  alias Leaf.Dates
  alias Leaf.Leave
  alias Leaf.Leave.BalanceEntry
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

  @forever ~D[9999-12-31]

  @doc """
  An account for each leave type the person holds one in, as at `as_at`, in the organisation's
  order.

  `as_at` says how far the person has accrued, and nothing about which of their leave counts: every
  day of approved leave draws the balance down whether they have been on it yet or not, since leave
  they are already going on is spent whatever the calendar says.

  A leave type appears where the person holds a balance in it — something granted to them, entered
  by hand, or filed against it. A type that grants nothing and is recorded only appears once there
  is leave against it, so what somebody *may* request comes from their policy, not from here.

  `days` are leave to count alongside what is approved, which is what answers what a balance would
  be were a request approved. The account accrues on to the last of them where they run past
  `as_at`, since leave is affordable out of what will have been accrued by the time it is taken.
  What is already approved stays counted either way, so projecting an *amendment* means leaving
  that request's own days out of `days`.
  """
  @spec statements(Person.t(), Date.t(), [Day.t()]) :: [Statement.t()]
  def statements(person, as_at, days \\ []) do
    %{organisation: organisation} = person = People.dated(person)
    as_at = Enum.reduce(days, as_at, &Enum.max([&1.date, &2], Date))
    spans = Span.all(person, organisation, as_at)
    leave_types = Policies.leave_types(organisation.id)
    taken = Leave.days_approved(person) ++ days
    hours = hours_taken_against(person, taken)

    context = %{
      organisation: organisation,
      as_at: as_at,
      holidays: observed_holidays(person, spans),
      spans: spans,
      entered: lapsing(person, Leave.balance_entries(person, as_at)),
      taken: taken,
      hours: hours,
      suspended: suspended(taken, leave_types, hours)
    }

    Enum.flat_map(leave_types, &statement(&1, context))
  end

  @doc """
  The accounts that hold a balance, in the organisation's order.

  `statements/3` less the types that are recorded only, being those outside `granted/1`: one the
  person is granted nothing in has no balance to show, and a figure for it would only be the leave
  taken, with a minus in front.
  """
  @spec balances(Person.t(), Date.t(), [Day.t()]) :: [Statement.t()]
  def balances(person, as_at, days \\ []) do
    granted = granted(person)

    person |> statements(as_at, days) |> Enum.filter(&MapSet.member?(granted, &1.leave_type.id))
  end

  @doc """
  The leave types the person has ever been granted anything in, by a policy or by hand.

  By a policy is an entitlement that grants something while they were employed and on it; by hand
  is a balance entry adding to the balance. Every other type is recorded only for them. That is a
  fact about the person rather than about a date, so it is read over all of their history: a type
  does not turn recorded only by being read before its first grant.
  """
  @spec granted(Person.t()) :: MapSet.t(Ecto.UUID.t())
  def granted(person) do
    by_policy = Enum.map(lives(person), fn {_life, entitlement} -> entitlement end)
    by_hand = person |> Leave.balance_entries() |> Enum.filter(&Decimal.positive?(&1.amount))

    MapSet.new(by_policy ++ by_hand, & &1.leave_type_id)
  end

  @doc """
  Every balance figure entered for the person, oldest first, each with the date it lapses on.

  An entry lapses with the entitlement it is held under, like anything that entitlement granted
  (§4.8), so it lapses on its own `expires_on` or that entitlement's `effective_to`, whichever comes
  first, and nil where neither does.
  """
  @spec balance_entries(Person.t()) :: [{BalanceEntry.t(), Date.t() | nil}]
  def balance_entries(person), do: lapsing(person, Leave.balance_entries(person))

  defp lapsing(person, entries) do
    lives = lives(person)

    Enum.map(entries, &{&1, Dates.earliest(&1.expires_on, ends_on(&1, lives))})
  end

  # Each entitlement that grants the person something, over the part of its life they are on it.
  defp lives(person) do
    employed = Date.range(person.employment_start_date, person.employment_end_date || @forever)

    for {span, policy} <- People.leave_policy_segments(person, employed),
        entitlement <- Policies.entitlements(policy.id, span),
        entitlement.amount_source != :none,
        {:ok, life} <- [
          Dates.intersect(span, entitlement.effective_from, entitlement.effective_to)
        ],
        do: {life, entitlement}
  end

  # Where two entitlements' lives overlap, the entry is held under the one that succeeded the other,
  # as a cap is (`Leaf.Ledger.Grant`). One dated before any entitlement reached the person — an
  # opening balance brought in ahead of go-live — is held under the first that did.
  defp ends_on(entry, lives) do
    of_type =
      for {life, held} <- lives, held.leave_type_id == entry.leave_type_id, do: {life, held}

    case for({life, held} <- of_type, entry.date in life, do: held) do
      [] -> of_type |> first_after(entry.date) |> effective_to()
      holding -> Enum.max_by(holding, & &1.effective_from, Date).effective_to
    end
  end

  defp first_after(lives, date) do
    lives
    |> Enum.filter(fn {life, _held} -> Date.after?(life.first, date) end)
    |> Enum.min_by(fn {life, _held} -> life.first end, Date, fn -> {nil, nil} end)
    |> elem(1)
  end

  defp effective_to(nil), do: nil
  defp effective_to(entitlement), do: entitlement.effective_to

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

  @doc """
  The accounts `days` would leave behind, in the organisation's order.

  Only the leave types those days draw on, out of `balances/3`: what approving a request comes to
  is a question about what it draws and not about everything the person holds, and a type that is
  recorded only has no balance to come out under. A balance that comes out under nothing is an
  answer rather than a refusal — leave may be taken in advance (§5.2), so nothing here blocks
  anybody.
  """
  @spec projected(Person.t(), [Day.t()]) :: [Statement.t()]
  def projected(person, days) do
    today = People.today(person)

    case ready?(person, today) do
      false -> []
      true -> drawing_on(person, today, days)
    end
  end

  defp drawing_on(person, today, days) do
    drawn = MapSet.new(days, & &1.leave_type_id)

    person
    |> balances(today, days)
    |> Enum.filter(&MapSet.member?(drawn, &1.leave_type.id))
  end

  @doc """
  What each leave type has been asked for and not yet decided, in the unit the type counts in.

  A leave type nothing is waiting on is left out, so the map says what it has to say and nothing
  more. This draws no balance down: undecided leave is neither held nor spent until somebody says.
  """
  @spec awaiting(Person.t()) :: %{Ecto.UUID.t() => Decimal.t()}
  def awaiting(person) do
    days = Leave.days_awaiting(person)
    leave_types = Policies.leave_types(person.organisation_id)
    units = Map.new(leave_types, &{&1.id, &1.unit})
    hours = hours_taken_against(person, days)

    days
    |> Enum.group_by(& &1.leave_type_id)
    |> Map.new(fn {leave_type_id, days} ->
      {leave_type_id, asked(days, units[leave_type_id], hours)}
    end)
  end

  @doc """
  Whether everything a balance is worked out from is on record for the person.

  `statements/3` and `awaiting/1` refuse a stretch of somebody's history with no work pattern
  behind it, because hours nobody knows cannot be pro-rated and reading them as none would be a
  wrong figure rather than a small one. A page asks here first, so that somebody half set up reads
  as half set up.

  That stretch runs from the first date tracked or the first day of leave filed, whichever is
  earlier: leave dated before tracking started is filed on a pattern reaching back over it, and
  removing that pattern leaves the leave with nothing to be measured against. A pattern runs on
  until the next supersedes it, so one in force on that first date is in force on every date after.
  """
  @spec ready?(Person.t(), Date.t()) :: boolean()
  def ready?(person, as_at) do
    {:ok, organisation} = Org.fetch_organisation(person.organisation_id)

    case Dates.earliest(tracked_from(person, organisation, as_at), Leave.first_filed_on(person)) do
      nil -> true
      from -> People.fetch_work_pattern_on(person, from) != :error
    end
  end

  defp tracked_from(person, organisation, as_at) do
    case Span.tracked_range(person, organisation, as_at) do
      :error -> nil
      {:ok, range} -> range.first
    end
  end

  defp statement(leave_type, context) do
    spans = Enum.filter(context.spans, &(&1.entitlement.leave_type_id == leave_type.id))

    entered =
      for {entry, _lapses_on} = row <- context.entered, of_type?(entry, leave_type), do: row

    taken = Enum.filter(context.taken, &of_type?(&1, leave_type))

    case {spans, entered, taken} do
      {[], [], []} -> []
      _held -> [replay(leave_type, context, spans, entered, taken)]
    end
  end

  defp of_type?(row, leave_type), do: row.leave_type_id == leave_type.id

  defp asked(days, unit, hours) do
    Enum.reduce(days, Decimal.new(0), &Decimal.add(&2, Leave.in_unit(&1, unit, hours[&1.date])))
  end

  defp replay(leave_type, context, spans, entered, taken) do
    %{organisation: organisation, holidays: holidays, suspended: suspended} = context
    dates = Enum.map(taken, & &1.date)

    movements =
      Enum.flat_map(spans, &Grant.movements(&1, organisation, holidays, suspended, dates)) ++
        Enum.map(entered, &entered_movement/1) ++
        Enum.map(taken, &taken_movement(&1, leave_type, context.hours))

    {movements, lots} = Drawdown.run(movements, Grant.caps(spans), context.as_at)

    Statement.new(leave_type, context.as_at, movements, lots)
  end

  defp entered_movement({entry, lapses_on}) do
    %Movement{
      date: entry.date,
      kind: entry.kind,
      amount: entry.amount,
      expires_on: lapses_on
    }
  end

  defp taken_movement(day, leave_type, hours) do
    amount = Leave.in_unit(day, leave_type.unit, hours[day.date])

    %Movement{date: day.date, kind: :taken, amount: Decimal.negate(amount)}
  end

  # The hours the request and the calendar are measured against, public holidays granted off
  # included, so a day off one draws what it is worth on the date now rather than when it was filed.
  # Every day is filed with hours on record, and `ready?/2` says where a pattern removed since has
  # left one without.
  defp hours_taken_against(_person, []), do: %{}

  defp hours_taken_against(person, days) do
    span = Dates.spanning(Enum.map(days, & &1.date))
    person |> Leave.hours_per_day!(span) |> Map.new()
  end

  defp suspended(taken, leave_types, hours) do
    suspending = leave_types |> Enum.filter(& &1.suspends_accrual) |> MapSet.new(& &1.id)

    for day <- taken, day.leave_type_id in suspending do
      {day.date, Leave.in_unit(day, :hours, hours[day.date])}
    end
  end

  # A public holiday allowance is counted over the range its grant is measured over, which for a
  # block grant is a whole period and so may run past the date being asked about, so the calendar
  # is read over those rather than the range. Nothing else needs it, so nothing else pays for
  # reading it.
  defp observed_holidays(person, spans) do
    spans
    |> Enum.filter(&(&1.entitlement.amount_source == :public_holidays))
    |> Enum.flat_map(&Grant.measured/1)
    |> counted_holidays(person)
  end

  defp counted_holidays([], _person), do: []

  defp counted_holidays(ranges, person) do
    holidays(person, Dates.spanning(Enum.flat_map(ranges, &[&1.first, &1.last])))
  end

  # The count claims to be the period's whole share of the calendar, so a period the person is on no
  # calendar over part of would be quietly short of one.
  defp holidays(person, range) do
    person |> People.public_holidays!(range) |> Enum.map(& &1.date)
  end
end
