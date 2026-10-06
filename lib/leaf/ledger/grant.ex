defmodule Leaf.Ledger.Grant do
  @moduledoc """
  What a covered span grants, and when what it grants lapses.

  A block grant lands whole on the first day of its period; an accrual lands at the end of each
  span, worth the part of the period that span is. An accrual also lands on each day leave of its
  type is taken inside the span, worth what has accrued since the last, so that leave draws on what
  had accrued by its date and nothing more. Either way the amount is pro-rated in a single division
  — the hours worked and the days elapsed multiplied together before dividing once — so that the
  pieces of a span sum back to the span, and a year of accruals to the year's entitlement, instead
  of drifting by a rounding error per piece. Suspended leave is the exception: it is measured
  piece by piece, below. A piece lapses when the accrual it was cut from would
  have, so taking leave does not bring a lapse forward.

  Leave of a type that suspends accrual takes its share of the person's working time out of an
  accrual, in the same division: a piece earns `normal × (1 − suspended hours ÷ scheduled hours)`
  over its own dates, so what leave drew on is what had accrued by then, whatever is suspended
  later. Measuring in hours rather than dates leaves the weekends inside a stretch of it unworked
  too, and suspends a half day by half. A block grant is not an accrual and is never reduced (§4.7),
  and nor is a public holiday allowance, which counts holidays rather than time.
  """

  alias Leaf.Dates
  alias Leaf.Ledger.Movement
  alias Leaf.Ledger.Span
  alias Leaf.Org.Organisation
  alias Leaf.People

  @doc """
  What the covered span grants, if anything.

  `holidays` are the dates the person observes as public holidays, which is what an entitlement
  drawn from the holiday calendar is measured in. `suspended` is the hours of each day of leave
  that suspends accrual. `taken` is the dates leave of the span's type is taken on.
  """
  @spec movements(Span.t(), Organisation.t(), [Date.t()], [{Date.t(), Decimal.t()}], [Date.t()]) ::
          [Movement.t()]
  def movements(span, organisation, holidays, suspended, taken) do
    span
    |> measured()
    |> Enum.flat_map(&pieces(span.entitlement.grant_timing, &1, taken))
    |> Enum.map(&arrival(span, &1, organisation, holidays, suspended))
    |> Enum.reject(&Decimal.equal?(&1.amount, 0))
  end

  # Each piece with the range it was cut from.
  defp pieces(:period_start, measured, _taken), do: [{measured, measured}]

  defp pieces(:daily, measured, taken) do
    {pieces, _next} =
      taken
      |> Enum.filter(&(&1 in measured))
      |> Enum.concat([measured.last])
      |> Enum.sort(Date)
      |> Enum.dedup()
      |> Enum.map_reduce(measured.first, &{{Date.range(&2, &1), measured}, Date.add(&1, 1)})

    pieces
  end

  @doc """
  The range a span's amount is measured over, or none where it grants nothing.

  An accrual is measured over the span it lands at the end of. A block grant is measured over its
  whole grant period, which can open before the span does and run past the date being asked about,
  and only a span that starts granting when its period does holds one — which is what leaves
  someone who joined part-way through a period without one until the next period starts. The one
  block measured in something other than dates — a share of the holiday calendar — stops where the
  person's employment does.
  """
  @spec measured(Span.t()) :: [Date.Range.t()]
  def measured(%{granting: nil}), do: []

  def measured(%{entitlement: %{grant_timing: :period_start}} = span) do
    case Date.compare(span.granting.first, span.period.first) do
      :eq -> [block(span)]
      _ -> []
    end
  end

  def measured(span), do: [span.granting]

  # An allowance drawn from the holiday calendar is the share of it the person observes, so a period
  # they leave part-way through is measured only as far as they are there for. A fixed amount is a
  # block whatever the period holds, and §4.7 deliberately does not pro-rate a partial one.
  defp block(%{entitlement: %{amount_source: :public_holidays}} = span) do
    Date.range(span.period.first, Dates.earliest(span.period.last, span.employed_to))
  end

  defp block(span), do: span.period

  @doc """
  The end of each grant period over which a leave type rolls over only up to a cap.

  A cap falls due at a period end the person was actually covered for, so a period their
  entitlement stopped part-way through does not trim a balance it no longer governs.
  """
  @spec caps([Span.t()]) :: [{Date.t(), Decimal.t()}]
  def caps(spans) do
    spans
    |> Enum.filter(&capped?/1)
    |> Enum.group_by(& &1.period.last, & &1.entitlement)
    |> Enum.map(fn {date, entitlements} -> {date, governing(entitlements, date).rollover_cap} end)
  end

  defp capped?(%{entitlement: %{expiry_rule: :cap}} = span) do
    Date.compare(span.dates.last, span.period.last) == :eq
  end

  defp capped?(_span), do: false

  # A succession hands over part-way through a period, so both entitlements govern its end and only
  # one cap can fall due there: the one still granting, since those are the terms in force — and no
  # two grant windows overlap, so there is at most one. Where neither is, granting has stopped
  # altogether and the cap still trims what it left behind, under the last terms to have granted.
  defp governing(entitlements, date) do
    Enum.find(entitlements, &granting_on?(&1, date)) ||
      Enum.max_by(entitlements, & &1.effective_from, Date)
  end

  defp granting_on?(%{granted_to: nil}, _date), do: true
  defp granting_on?(entitlement, date), do: not Date.before?(entitlement.granted_to, date)

  defp arrival(span, {piece, measured}, organisation, holidays, suspended) do
    {kind, date} = lands(span.entitlement.grant_timing, piece)
    {_kind, whole_lands_on} = lands(span.entitlement.grant_timing, measured)

    %Movement{
      date: date,
      kind: kind,
      amount: amount(span, piece, organisation, holidays, suspended),
      expires_on: expires_on(span.entitlement, span.period, whole_lands_on)
    }
  end

  defp lands(:period_start, measured), do: {:grant, measured.first}
  defp lands(:daily, measured), do: {:accrual, measured.last}

  defp amount(span, measured, organisation, holidays, suspended) do
    {base, num, den} = measure(span.entitlement, measured, span.period, organisation, holidays)
    {num, den} = by_hours_worked(span, organisation, num, den)
    {num, den} = by_time_suspended(span, measured, suspended, num, den)

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

  # A piece the person suspended no time in is left alone, which is also what keeps one they are
  # scheduled no hours over from being divided by none.
  defp by_time_suspended(
         %{entitlement: %{amount_source: :fixed, grant_timing: :daily}} = span,
         measured,
         suspended,
         num,
         den
       ) do
    lost = total(for {date, hours} <- suspended, date in measured, do: hours)

    case Decimal.positive?(lost) do
      false ->
        {num, den}

      true ->
        scheduled = total(Enum.map(measured, &People.hours_on(span.work_pattern, &1)))
        {Decimal.mult(num, Decimal.sub(scheduled, lost)), Decimal.mult(den, scheduled)}
    end
  end

  defp by_time_suspended(_span, _measured, _suspended, num, den), do: {num, den}

  defp total(hours), do: Enum.reduce(hours, Decimal.new(0), &Decimal.add/2)

  defp expires_on(entitlement, period, granted_on) do
    Dates.earliest(lapses_on(entitlement, period, granted_on), entitlement.effective_to)
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
end
