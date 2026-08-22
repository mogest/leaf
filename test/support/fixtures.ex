defmodule Leaf.Fixtures do
  @moduledoc "Minimal persisted records for tests, built through the schemas' own changesets."

  alias Leaf.Leave.BalanceEntry
  alias Leaf.Leave.Request
  alias Leaf.Org.HolidayCalendar
  alias Leaf.Org.Organisation
  alias Leaf.Org.PublicHoliday
  alias Leaf.People.Person
  alias Leaf.People.PersonHolidayCalendar
  alias Leaf.People.PersonPolicyAssignment
  alias Leaf.People.WorkPattern
  alias Leaf.Policies.LeavePolicy
  alias Leaf.Policies.LeaveType
  alias Leaf.Policies.PolicyEntitlement
  alias Leaf.Repo

  @start_date ~D[2024-03-04]

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
      expiry_rule: :never,
      allow_negative: false
    })
  end

  @spec policy_assignment(map()) :: PersonPolicyAssignment.t()
  def policy_assignment(attrs \\ %{}) do
    insert(%PersonPolicyAssignment{}, &PersonPolicyAssignment.changeset/2, attrs, %{
      effective_from: @start_date
    })
  end

  @spec holiday_calendar(map()) :: HolidayCalendar.t()
  def holiday_calendar(attrs \\ %{}) do
    insert(%HolidayCalendar{}, &HolidayCalendar.changeset/2, attrs, %{
      name: "New Zealand",
      country_code: "NZ"
    })
  end

  @spec calendar_assignment(map()) :: PersonHolidayCalendar.t()
  def calendar_assignment(attrs \\ %{}) do
    insert(%PersonHolidayCalendar{}, &PersonHolidayCalendar.changeset/2, attrs, %{
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

  @spec leave_request(map()) :: Request.t()
  def leave_request(attrs) do
    insert(%Request{}, &Request.changeset/2, attrs, %{status: :approved})
  end

  @spec balance_entry(map()) :: BalanceEntry.t()
  def balance_entry(attrs) do
    insert(%BalanceEntry{}, &BalanceEntry.changeset/2, attrs, %{
      date: ~D[2024-01-01],
      kind: :opening_balance,
      amount: "0"
    })
  end

  defp insert(struct, changeset, attrs, defaults) do
    struct |> changeset.(Map.merge(defaults, attrs)) |> Repo.insert!()
  end
end
