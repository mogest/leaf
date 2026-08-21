defmodule Leaf.Seed do
  @moduledoc """
  Builds an example organisation: a New Zealand leave policy, its holiday calendar, and a person.

  For local development, and as a worked example of how the entitlements in `SCOPE.md` are actually
  configured. Everything goes in through the contexts, so a policy that will not validate fails
  here rather than reaching the database.
  """

  alias Leaf.Org
  alias Leaf.Org.Organisation
  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.Policies
  alias Leaf.Policies.LeavePolicy

  @organisation %{
    name: "Fernbank Collective",
    full_time_week_hours: "40",
    standard_day_hours: "8",
    year_start_month: 4,
    tracked_from: ~D[2024-01-01]
  }

  @calendar %{name: "New Zealand", country_code: "NZ"}

  @policy_name "New Zealand employee"

  # Before anyone's employment starts, so a person's own dates are what bound their entitlement.
  @policy_from ~D[2024-01-01]

  # The leave type comes first because its unit is what the amounts below are counted in, and its
  # position in this list is its position in the organisation's list of types.
  @entitlements [
    %{
      leave_type: {"Annual leave", :hours},
      amount_source: :fixed,
      grant_amount: "200",
      grant_basis: :employment_date,
      grant_period: :year,
      grant_timing: :daily,
      pro_rated_by_fte: true,
      expiry_rule: :never,
      allow_negative: false,
      excess_threshold: "300"
    },
    %{
      leave_type: {"Sick leave", :days},
      amount_source: :fixed,
      grant_amount: "20",
      grant_basis: :employment_date,
      grant_period: :year,
      grant_timing: :period_start,
      pro_rated_by_fte: false,
      expiry_rule: :cap,
      rollover_cap: "20",
      allow_negative: false
    },
    %{
      leave_type: {"Quarterly leave", :hours},
      amount_source: :fixed,
      grant_amount: "8",
      grant_basis: :calendar_year,
      grant_period: :quarter,
      grant_timing: :period_start,
      pro_rated_by_fte: true,
      expiry_rule: :grant_period_end,
      allow_negative: false
    },
    %{
      leave_type: {"Birthday leave", :days},
      amount_source: :fixed,
      grant_amount: "1",
      grant_basis: :birthday,
      grant_period: :year,
      grant_timing: :period_start,
      pro_rated_by_fte: false,
      expiry_rule: :window,
      expiry_window_days: 14,
      allow_negative: true
    },
    %{
      leave_type: {"Longevity leave", :days},
      amount_source: :fixed,
      grant_amount: "1",
      grant_basis: :employment_date,
      grant_period: :year,
      grant_timing: :period_start,
      pro_rated_by_fte: false,
      expiry_rule: :grant_period_end,
      allow_negative: false
    },
    %{
      leave_type: {"Bereavement leave", :days},
      amount_source: :none,
      pro_rated_by_fte: false,
      expiry_rule: :never,
      allow_negative: true
    }
  ]

  @person %{
    name: "Mog",
    email: "mog@example.test",
    role: :admin,
    employment_start_date: ~D[2024-12-15],
    birth_date: ~D[1990-08-10]
  }

  # 36 hours against a 40 hour week: 0.9 FTE.
  @work_pattern %{
    monday_hours: "9",
    tuesday_hours: "9",
    wednesday_hours: "9",
    thursday_hours: "0",
    friday_hours: "9",
    saturday_hours: "0",
    sunday_hours: "0"
  }

  # New Zealand's national public holidays, on the dates they are observed rather than the dates
  # they fall — a Saturday holiday is taken on the following Monday. Regional anniversary days are
  # not here; an organisation with staff outside one region would hold a calendar per region.
  @public_holidays [
    {~D[2025-01-01], "New Year's Day"},
    {~D[2025-01-02], "Day after New Year's Day"},
    {~D[2025-02-06], "Waitangi Day"},
    {~D[2025-04-18], "Good Friday"},
    {~D[2025-04-21], "Easter Monday"},
    {~D[2025-04-25], "ANZAC Day"},
    {~D[2025-06-02], "King's Birthday"},
    {~D[2025-06-20], "Matariki"},
    {~D[2025-10-27], "Labour Day"},
    {~D[2025-12-25], "Christmas Day"},
    {~D[2025-12-26], "Boxing Day"},
    {~D[2026-01-01], "New Year's Day"},
    {~D[2026-01-02], "Day after New Year's Day"},
    {~D[2026-02-06], "Waitangi Day"},
    {~D[2026-04-03], "Good Friday"},
    {~D[2026-04-06], "Easter Monday"},
    {~D[2026-04-27], "ANZAC Day (observed)"},
    {~D[2026-06-01], "King's Birthday"},
    {~D[2026-07-10], "Matariki"},
    {~D[2026-10-26], "Labour Day"},
    {~D[2026-12-25], "Christmas Day"},
    {~D[2026-12-28], "Boxing Day (observed)"},
    {~D[2027-01-01], "New Year's Day"},
    {~D[2027-01-04], "Day after New Year's Day (observed)"},
    {~D[2027-02-08], "Waitangi Day (observed)"},
    {~D[2027-03-26], "Good Friday"},
    {~D[2027-03-29], "Easter Monday"},
    {~D[2027-04-26], "ANZAC Day (observed)"},
    {~D[2027-06-07], "King's Birthday"},
    {~D[2027-06-25], "Matariki"},
    {~D[2027-10-25], "Labour Day"},
    {~D[2027-12-27], "Christmas Day (observed)"},
    {~D[2027-12-28], "Boxing Day (observed)"}
  ]

  @doc """
  Builds the whole example, returning what it made.

  Raises on anything that will not validate. Expects an empty database — the caller checks that.
  """
  @spec run() :: %{organisation: Organisation.t(), policy: LeavePolicy.t(), person: Person.t()}
  def run do
    organisation = add_organisation()
    calendar = add_calendar(organisation)
    policy = add_policy(organisation)
    person = add_person(organisation, policy, calendar)

    %{organisation: organisation, policy: policy, person: person}
  end

  defp add_organisation do
    {:ok, organisation} = Org.create_organisation(@organisation)

    organisation
  end

  defp add_calendar(organisation) do
    {:ok, calendar} =
      Org.create_holiday_calendar(Map.put(@calendar, :organisation_id, organisation.id))

    Enum.each(@public_holidays, fn {date, name} ->
      {:ok, _holiday} =
        Org.create_public_holiday(%{
          holiday_calendar_id: calendar.id,
          date: date,
          name: name
        })
    end)

    calendar
  end

  defp add_policy(organisation) do
    {:ok, policy} =
      Policies.create_leave_policy(%{organisation_id: organisation.id, name: @policy_name})

    @entitlements
    |> Enum.with_index(1)
    |> Enum.each(fn {entitlement, position} ->
      add_entitlement(organisation, policy, entitlement, position)
    end)

    policy
  end

  defp add_entitlement(organisation, policy, entitlement, position) do
    {name, unit} = entitlement.leave_type

    {:ok, leave_type} =
      Policies.create_leave_type(%{
        organisation_id: organisation.id,
        name: name,
        unit: unit,
        position: position
      })

    {:ok, _entitlement} =
      entitlement
      |> Map.delete(:leave_type)
      |> Map.merge(%{
        leave_policy_id: policy.id,
        leave_type_id: leave_type.id,
        effective_from: @policy_from
      })
      |> Policies.create_entitlement()
  end

  defp add_person(organisation, policy, calendar) do
    started_on = @person.employment_start_date

    {:ok, person} = People.create_person(Map.put(@person, :organisation_id, organisation.id))

    {:ok, _pattern} =
      @work_pattern
      |> Map.merge(%{person_id: person.id, effective_from: started_on})
      |> People.create_work_pattern()

    {:ok, _assignment} =
      People.assign_leave_policy(%{
        person_id: person.id,
        leave_policy_id: policy.id,
        effective_from: started_on
      })

    {:ok, _assignment} =
      People.assign_holiday_calendar(%{
        person_id: person.id,
        holiday_calendar_id: calendar.id,
        effective_from: started_on
      })

    person
  end
end
