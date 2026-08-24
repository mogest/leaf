defmodule Leaf.Fixtures do
  @moduledoc """
  Minimal persisted records for tests, built through the schemas' own changesets.

  The contexts are the way in for real code; these skip them because a fixture wants no actor and
  no audit entry. What a record belongs to is no longer castable, so any `_id` given here is set
  on the struct, exactly as the contexts set it.
  """

  alias Leaf.Leave.BalanceEntry
  alias Leaf.Leave.Request
  alias Leaf.Org.Calendar
  alias Leaf.Org.Organisation
  alias Leaf.Org.PublicHoliday
  alias Leaf.People.Person
  alias Leaf.People.PersonCalendar
  alias Leaf.People.PersonPolicyAssignment
  alias Leaf.People.WorkPattern
  alias Leaf.Policies.LeavePolicy
  alias Leaf.Policies.LeaveType
  alias Leaf.Policies.PolicyEntitlement
  alias Leaf.Repo

  @start_date ~D[2024-03-04]

  @recorded_only %{
    amount_source: :none,
    grant_amount: nil,
    grant_basis: nil,
    grant_period: nil,
    grant_timing: nil
  }

  @spec organisation(map()) :: Organisation.t()
  def organisation(attrs \\ %{}) do
    insert(%Organisation{}, &Organisation.changeset/2, attrs, %{
      name: "Fernbank Collective",
      full_time_week_hours: "40",
      standard_day_hours: "8",
      year_start_month: 4,
      tracked_from: ~D[2024-01-01]
    })
  end

  @spec person(map()) :: Person.t()
  def person(attrs \\ %{}) do
    insert(%Person{}, &Person.changeset/2, attrs, %{
      name: "Rae Halloran",
      email: "rae#{System.unique_integer([:positive])}@example.test",
      role: :member,
      employment_start_date: @start_date
    })
  end

  @spec work_pattern(map()) :: WorkPattern.t()
  def work_pattern(attrs \\ %{}) do
    insert(%WorkPattern{}, &WorkPattern.changeset/2, attrs, %{
      effective_from: @start_date,
      monday_hours: "8",
      tuesday_hours: "8",
      wednesday_hours: "8",
      thursday_hours: "8",
      friday_hours: "8",
      saturday_hours: "0",
      sunday_hours: "0"
    })
  end

  @spec leave_type(map()) :: LeaveType.t()
  def leave_type(attrs \\ %{}) do
    insert(%LeaveType{}, &LeaveType.changeset/2, attrs, %{
      name: "Annual leave",
      unit: :hours,
      position: 1
    })
  end

  @spec leave_policy(map()) :: LeavePolicy.t()
  def leave_policy(attrs \\ %{}) do
    insert(%LeavePolicy{}, &LeavePolicy.changeset/2, attrs, %{name: "Standard employee"})
  end

  @spec policy_entitlement(map()) :: PolicyEntitlement.t()
  def policy_entitlement(attrs \\ %{}) do
    insert(%PolicyEntitlement{}, &PolicyEntitlement.changeset/2, attrs, %{
      effective_from: @start_date,
      amount_source: :fixed,
      grant_amount: "160",
      grant_basis: :employment_date,
      grant_period: :year,
      grant_timing: :daily,
      pro_rated_by_fte: true,
      expiry_rule: :never
    })
  end

  @spec policy_assignment(map()) :: PersonPolicyAssignment.t()
  def policy_assignment(attrs \\ %{}) do
    insert(%PersonPolicyAssignment{}, &PersonPolicyAssignment.changeset/2, attrs, %{
      effective_from: @start_date
    })
  end

  @doc """
  A policy offering `leave_type_id`, assigned to `person_id` — what filing leave against it needs.

  It grants nothing, so a balance is whatever the test puts in it and nothing else; pass
  `amount_source` and the grant fields where the point is what it grants. Returns the entitlement,
  whose `leave_policy_id` is the policy anything further hangs off — give that instead of the person
  to offer a second type on a policy they are already on.
  """
  @spec offering(map()) :: PolicyEntitlement.t()
  def offering(%{leave_policy_id: _policy_id} = attrs) do
    policy_entitlement(Map.merge(@recorded_only, attrs))
  end

  def offering(attrs) do
    {person_id, attrs} = Map.pop!(attrs, :person_id)
    {organisation_id, attrs} = Map.pop!(attrs, :organisation_id)
    policy = leave_policy(%{organisation_id: organisation_id})

    policy_assignment(%{person_id: person_id, leave_policy_id: policy.id})
    offering(Map.put(attrs, :leave_policy_id, policy.id))
  end

  @spec calendar(map()) :: Calendar.t()
  def calendar(attrs \\ %{}) do
    insert(%Calendar{}, &Calendar.changeset/2, attrs, %{
      name: "New Zealand",
      country_code: "NZ",
      time_zone: "Pacific/Auckland"
    })
  end

  @spec calendar_assignment(map()) :: PersonCalendar.t()
  def calendar_assignment(attrs \\ %{}) do
    insert(%PersonCalendar{}, &PersonCalendar.changeset/2, attrs, %{
      effective_from: @start_date
    })
  end

  @spec public_holiday(map()) :: PublicHoliday.t()
  def public_holiday(attrs \\ %{}) do
    insert(%PublicHoliday{}, &PublicHoliday.changeset/2, attrs, %{
      name: "New Year's Day",
      date: ~D[2026-01-01]
    })
  end

  @doc """
  An approved request, whose `:days` are `t:Leaf.Leave.entry/0` maps.

  Who a request belongs to is not cast, so it is set on the struct here as `Leaf.Leave` does. Each
  day falls on a full day of the default pattern unless it says otherwise.
  """
  @spec leave_request(map()) :: Request.t()
  def leave_request(attrs) do
    {identity, attrs} = Map.split(attrs, [:person_id, :submitted_by_id, :status])

    %Request{status: :approved, submitted_by_id: identity[:person_id]}
    |> struct!(identity)
    |> Request.changeset(%{days: Enum.map(attrs.days, &worked/1)})
    |> Repo.insert!()
  end

  @spec balance_entry(map()) :: BalanceEntry.t()
  def balance_entry(attrs) do
    insert(%BalanceEntry{}, &BalanceEntry.changeset/2, attrs, %{
      date: ~D[2024-01-01],
      kind: :opening_balance,
      amount: "0"
    })
  end

  defp worked(day), do: Map.put_new(day, :hours_in_day, "8")

  defp insert(struct, changeset, attrs, defaults) do
    {identity, castable} = defaults |> Map.merge(attrs) |> Map.split_with(&identity?/1)

    struct |> struct!(identity) |> changeset.(castable) |> Repo.insert!()
  end

  defp identity?({field, _value}), do: field |> Atom.to_string() |> String.ends_with?("_id")
end
