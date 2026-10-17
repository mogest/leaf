defmodule Leaf.Policies.Granting do
  @moduledoc """
  When an entitlement grants a person anything, and which dates what it grants is measured over.

  Five windows have to agree before an entitlement grants anything on a date: the stretch of the
  person's history being asked about, the policy they were on then, the entitlement's own grant
  window, the service it asks for before it qualifies them, and the grant period the date falls in.
  Intersecting them is what makes a change part-way through a year split the year rather than
  replace it.

  This is the only place that knows when a grant lands, so that the balance a public holiday
  allowance credits and the days it makes working days are the same days.

  An entitlement anchored to a birthday covers nothing where the organisation holds no birth date,
  since there is no run of periods to place it in. That is deliberate and it is quiet: the person
  is granted no birthday leave and nothing says so.
  """

  alias Leaf.Dates
  alias Leaf.Org.Organisation
  alias Leaf.People.Person
  alias Leaf.Policies.GrantCycle
  alias Leaf.Policies.PolicyEntitlement

  @typedoc """
  One grant period of an entitlement, and the part of it the entitlement covers the person for.

  `covered` runs to the end of the entitlement's life and `granting` to the end of its grant window,
  which is the narrower of the two where a policy has stopped offering something people may still
  spend; nil where it grants nothing in the period at all.
  """
  @type window :: %{
          entitlement: PolicyEntitlement.t(),
          period: Date.Range.t(),
          covered: Date.Range.t(),
          granting: Date.Range.t() | nil
        }

  @doc "Each grant period of `entitlement` overlapping `assigned`, a stretch the person is on its policy."
  @spec windows(PolicyEntitlement.t(), Person.t(), Organisation.t(), Date.Range.t()) :: [window()]
  def windows(%{amount_source: :none}, _person, _organisation, _assigned), do: []

  def windows(entitlement, person, organisation, assigned) do
    qualified_on = qualified_on(entitlement, person)

    with {:ok, served} <- Dates.intersect(assigned, qualified_on, nil),
         {:ok, life} <-
           Dates.intersect(served, entitlement.effective_from, entitlement.effective_to),
         {:ok, cycle} <- cycle(entitlement, anchors(qualified_on, person, organisation)) do
      for period <- GrantCycle.periods_overlapping(cycle, life) do
        {:ok, covered} = Dates.intersect(life, period.first, period.last)

        %{
          entitlement: entitlement,
          period: period,
          covered: covered,
          granting: granting(covered, entitlement.granted_to)
        }
      end
    else
      :error -> []
    end
  end

  @doc "The ranges a grant is measured over, as `Leaf.Policies.measured/4`."
  @spec measured(PolicyEntitlement.t(), Date.Range.t(), Date.Range.t() | nil, Date.t() | nil) ::
          [Date.Range.t()]
  def measured(_entitlement, _period, nil, _employed_to), do: []

  def measured(%{grant_timing: :period_start} = entitlement, period, granting, employed_to) do
    case Date.compare(granting.first, period.first) do
      :eq -> [block(entitlement, period, employed_to)]
      _later -> []
    end
  end

  def measured(_entitlement, _period, granting, _employed_to), do: [granting]

  # An allowance drawn from the holiday calendar is the share of it the person observes, so a period
  # they leave, or the allowance ends, part-way through is measured only as far as that. A fixed
  # amount is a block whatever the period holds, and §4.7 deliberately does not pro-rate a partial
  # one.
  defp block(%{amount_source: :public_holidays} = entitlement, period, employed_to) do
    last = period.last |> Dates.earliest(employed_to) |> Dates.earliest(entitlement.effective_to)

    Date.range(period.first, last)
  end

  defp block(_entitlement, period, _employed_to), do: period

  defp granting(dates, granted_to) do
    case Dates.intersect(dates, dates.first, granted_to) do
      :error -> nil
      {:ok, granting} -> granting
    end
  end

  defp qualified_on(entitlement, person),
    do: Date.shift(person.employment_start_date, month: entitlement.qualifying_months || 0)

  defp anchors(qualified_on, person, organisation) do
    %{
      employment_start_date: person.employment_start_date,
      qualified_on: qualified_on,
      birth_date: person.birth_date,
      year_start_month: organisation.year_start_month
    }
  end

  defp cycle(entitlement, anchors) do
    with {:ok, {month, day}} <- anchor(entitlement.grant_basis, anchors) do
      {:ok, GrantCycle.new(month, day, entitlement.grant_period)}
    end
  end

  # A birth date is the one anchor an organisation genuinely may not hold; the others are columns
  # that cannot be null, so a missing one is a coding error and crashes here rather than granting.
  #
  # The day is the start date's rather than the qualifying date's, which may have been clamped to a
  # short month: periods pinned to the 31st still reach the 31st where there is one.
  defp anchor(:employment_date, %{employment_start_date: start, qualified_on: qualified_on}),
    do: {:ok, {qualified_on.month, start.day}}

  defp anchor(:birthday, %{birth_date: %Date{} = date}), do: {:ok, {date.month, date.day}}
  defp anchor(:birthday, _anchors), do: :error
  defp anchor(:calendar_year, _anchors), do: {:ok, {1, 1}}
  defp anchor(:organisation_year, %{year_start_month: month}), do: {:ok, {month, 1}}
end
