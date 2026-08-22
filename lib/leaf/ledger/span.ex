defmodule Leaf.Ledger.Span do
  @moduledoc """
  A stretch of dates over which one entitlement, one grant period and one work pattern all hold.

  Five windows have to agree before an entitlement grants anything on a date: the person's
  employment, the policy they were on then, the entitlement's own grant window, the grant period
  the date falls in, and the date the organisation started tracking leave. Intersecting them is
  what makes a change part-way through a year split the year rather than replace it.

  This is the only place that knows there are five. Everything downstream is handed a stretch of
  dates, the period it sits in and the hours worked over it, and has only to measure them.

  `dates` runs to the end of the entitlement's life and `granting` to the end of its grant window,
  which is the narrower of the two where a policy has stopped offering something people may still
  spend. Grants come from `granting`; a rollover cap falls due at the end of a `period` that
  `dates` covers, since a balance that is still spendable is still subject to its cap.

  An entitlement anchored to a birthday covers nothing where the organisation holds no birth date,
  since there is no run of periods to place it in. That is deliberate and it is quiet: the person
  is granted no birthday leave and nothing says so.
  """

  alias Leaf.Ledger.GrantCycle
  alias Leaf.Org.Organisation
  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.People.WorkPattern
  alias Leaf.Policies
  alias Leaf.Policies.PolicyEntitlement

  @type t :: %__MODULE__{
          entitlement: PolicyEntitlement.t(),
          period: Date.Range.t(),
          dates: Date.Range.t(),
          granting: Date.Range.t() | nil,
          work_pattern: WorkPattern.t()
        }

  @enforce_keys [:entitlement, :period, :dates, :granting, :work_pattern]
  defstruct [:entitlement, :period, :dates, :granting, :work_pattern]

  @doc "Every span up to and including `as_at` over which the person is entitled to something."
  @spec all(Person.t(), Organisation.t(), Date.t()) :: [t()]
  def all(person, organisation, as_at) do
    case tracked_range(person, organisation, as_at) do
      :error ->
        []

      {:ok, range} ->
        context = %{
          anchors: anchors(person, organisation),
          patterns: People.work_pattern_segments!(person, range)
        }

        person
        |> People.leave_policy_segments(range)
        |> Enum.flat_map(fn {assigned, policy_id} ->
          policy_spans(context, policy_id, assigned)
        end)
    end
  end

  @doc """
  The stretch of the person's history a balance as at `as_at` is worked out over.

  Their employment, bounded below by the date the organisation started tracking leave and above by
  the date being asked about. `:error` where those leave nothing.
  """
  @spec tracked_range(Person.t(), Organisation.t(), Date.t()) :: {:ok, Date.Range.t()} | :error
  def tracked_range(person, organisation, as_at) do
    bounded(
      Enum.max([organisation.tracked_from, person.employment_start_date], Date),
      earliest(as_at, person.employment_end_date)
    )
  end

  defp anchors(person, organisation) do
    %{
      employment_start_date: person.employment_start_date,
      birth_date: person.birth_date,
      year_start_month: organisation.year_start_month
    }
  end

  defp policy_spans(context, policy_id, assigned) do
    policy_id
    |> Policies.entitlements(assigned)
    |> Enum.flat_map(&entitlement_spans(context, &1, assigned))
  end

  defp entitlement_spans(_context, %{amount_source: :none}, _assigned), do: []

  defp entitlement_spans(context, entitlement, assigned) do
    with {:ok, life} <- intersect(assigned, entitlement.effective_from, entitlement.effective_to),
         {:ok, cycle} <- cycle(context, entitlement) do
      cycle
      |> GrantCycle.periods_overlapping(life)
      |> Enum.flat_map(&period_spans(context, entitlement, &1, life))
    else
      :error -> []
    end
  end

  defp cycle(context, entitlement) do
    with {:ok, {month, day}} <- anchor(entitlement.grant_basis, context.anchors) do
      {:ok, GrantCycle.new(month, day, entitlement.grant_period)}
    end
  end

  # A birth date is the one anchor an organisation genuinely may not hold; the others are columns
  # that cannot be null, so a missing one is a coding error and crashes here rather than granting.
  defp anchor(:employment_date, %{employment_start_date: date}), do: {:ok, {date.month, date.day}}
  defp anchor(:birthday, %{birth_date: %Date{} = date}), do: {:ok, {date.month, date.day}}
  defp anchor(:birthday, _anchors), do: :error
  defp anchor(:calendar_year, _anchors), do: {:ok, {1, 1}}
  defp anchor(:organisation_year, %{year_start_month: month}), do: {:ok, {month, 1}}

  defp period_spans(context, entitlement, period, life) do
    {:ok, covered} = intersect(life, period.first, period.last)

    Enum.flat_map(context.patterns, fn {worked, pattern} ->
      pattern_span(entitlement, period, covered, worked, pattern)
    end)
  end

  defp pattern_span(entitlement, period, covered, worked, pattern) do
    case intersect(covered, worked.first, worked.last) do
      :error ->
        []

      {:ok, dates} ->
        [
          %__MODULE__{
            entitlement: entitlement,
            period: period,
            dates: dates,
            granting: granting(entitlement, dates),
            work_pattern: pattern
          }
        ]
    end
  end

  defp granting(entitlement, dates) do
    case intersect(dates, dates.first, entitlement.granted_to) do
      :error -> nil
      {:ok, granting} -> granting
    end
  end

  defp intersect(range, from, to) do
    bounded(Enum.max([range.first, from], Date), earliest(range.last, to))
  end

  defp bounded(first, last) do
    case Date.compare(first, last) do
      :gt -> :error
      _ -> {:ok, Date.range(first, last)}
    end
  end

  defp earliest(date, nil), do: date
  defp earliest(a, b), do: Enum.min([a, b], Date)
end
