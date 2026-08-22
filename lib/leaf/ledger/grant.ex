defmodule Leaf.Ledger.Grant do
  @moduledoc """
  What a covered span grants, and when what it grants lapses.

  A block grant lands whole on the first day of its period; an accrual lands at the end of each
  span, worth the part of the period that span is. Either way the amount is pro-rated in a single
  division — the hours worked and the days elapsed multiplied together before dividing once — so
  that a year of accruals sums back to the year's entitlement instead of drifting by a rounding
  error per span.
  """

  alias Leaf.Ledger.Movement
  alias Leaf.Ledger.Span
  alias Leaf.Org.Organisation
  alias Leaf.People

  @doc """
  What the covered span grants, if anything.

  `holidays` are the dates the person observes as public holidays, which is what an entitlement
  drawn from the holiday calendar is measured in.
  """
  @spec movements(Span.t(), Organisation.t(), [Date.t()]) :: [Movement.t()]
  def movements(span, organisation, holidays) do
    span
    |> measured()
    |> Enum.map(&arrival(span, &1, organisation, holidays))
    |> Enum.reject(&Decimal.equal?(&1.amount, 0))
  end

  @doc """
  The range a span's amount is measured over, or none where it grants nothing.

  An accrual is measured over the span it lands at the end of. A block grant is measured over its
  whole grant period, which can open before the span does and run past the date being asked about,
  and only a span that starts granting when its period does holds one — which is what leaves
  someone who joined part-way through a period without one until the next period starts.
  """
  @spec measured(Span.t()) :: [Date.Range.t()]
  def measured(%{granting: nil}), do: []

  def measured(%{entitlement: %{grant_timing: :period_start}} = span) do
    case Date.compare(span.granting.first, span.period.first) do
      :eq -> [span.period]
      _ -> []
    end
  end

  def measured(span), do: [span.granting]

  @doc """
  The end of each grant period over which a leave type rolls over only up to a cap.

  A cap falls due at a period end the person was actually covered for, so a period their
  entitlement stopped part-way through does not trim a balance it no longer governs.
  """
  @spec caps([Span.t()]) :: [{Date.t(), Decimal.t()}]
  def caps(spans) do
    spans
    |> Enum.filter(&capped?/1)
    |> Enum.map(&{&1.period.last, &1.entitlement.rollover_cap})
    |> Enum.uniq()
  end

  defp capped?(%{entitlement: %{expiry_rule: :cap}} = span) do
    Date.compare(span.dates.last, span.period.last) == :eq
  end

  defp capped?(_span), do: false

  defp arrival(span, measured, organisation, holidays) do
    {kind, date} = lands(span.entitlement.grant_timing, measured)

    %Movement{
      date: date,
      kind: kind,
      amount: amount(span, measured, organisation, holidays),
      expires_on: expires_on(span.entitlement, span.period, date)
    }
  end

  defp lands(:period_start, measured), do: {:grant, measured.first}
  defp lands(:daily, measured), do: {:accrual, measured.last}

  defp amount(span, measured, organisation, holidays) do
    {base, num, den} = measure(span.entitlement, measured, span.period, organisation, holidays)
    {num, den} = by_hours_worked(span, organisation, num, den)

    base |> Decimal.mult(num) |> Decimal.div(den)
  end

  defp measure(%{amount_source: :fixed} = entitlement, measured, period, _organisation, _holidays) do
    {entitlement.grant_amount, days(measured), days(period)}
  end

  # Counting the holidays that fall in the span measures the span already, so there is no further
  # fraction of the period to apply. A holiday is worth a day whatever day of the week it falls on,
  # which is a standard day's hours where the leave type counts in hours.
  defp measure(%{amount_source: :public_holidays} = entitlement, measured, _period, org, holidays) do
    observed = Enum.count(holidays, &within?(&1, measured))

    {Decimal.mult(observed, worth(entitlement.leave_type, org)), 1, 1}
  end

  defp worth(%{unit: :hours}, organisation), do: organisation.standard_day_hours
  defp worth(%{unit: :days}, _organisation), do: 1

  defp by_hours_worked(%{entitlement: %{pro_rated_by_fte: false}}, _organisation, num, den) do
    {num, den}
  end

  defp by_hours_worked(span, organisation, num, den) do
    {Decimal.mult(num, People.weekly_hours(span.work_pattern)),
     Decimal.mult(den, organisation.full_time_week_hours)}
  end

  defp expires_on(entitlement, period, granted_on) do
    earliest(lapses_on(entitlement, period, granted_on), entitlement.effective_to)
  end

  defp lapses_on(%{expiry_rule: :grant_period_end}, period, _granted_on), do: period.last

  defp lapses_on(%{expiry_rule: :window} = entitlement, _period, granted_on) do
    Date.add(granted_on, entitlement.expiry_window_days)
  end

  defp lapses_on(_entitlement, _period, _granted_on), do: nil

  defp days(range), do: Date.diff(range.last, range.first) + 1

  defp within?(date, range) do
    not (Date.before?(date, range.first) or Date.after?(date, range.last))
  end

  defp earliest(nil, date), do: date
  defp earliest(date, nil), do: date
  defp earliest(a, b), do: Enum.min([a, b], Date)
end
