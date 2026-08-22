defmodule Leaf.Seed do
  @moduledoc """
  Builds an example organisation with two New Zealand leave policies and somebody on each.

  Its holiday calendar comes with it. For local development, and as a worked example of how the
  entitlements in `SCOPE.md` are actually configured. Everything goes in through the contexts, so a
  policy that will not validate fails here rather than reaching the database.

  The two policies are the two treatments of public holidays in §4.9. An employee does not work
  them, so nothing in their policy mentions them at all; the contractor hybrid works them as
  ordinary days and holds an entitlement that credits their share of the calendar instead.

  Nobody has made any of it, so the audit log records the whole seed as the system.
  """

  alias Leaf.Org
  alias Leaf.Org.Organisation
  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.Policies
  alias Leaf.Policies.LeavePolicy

  # Nobody is seeding this: there is no administrator yet to attribute it to.
  @system nil

  @organisation %{
    name: "Fernbank Collective",
    full_time_week_hours: "40",
    standard_day_hours: "8",
    year_start_month: 4,
    tracked_from: ~D[2024-01-01]
  }

  @calendar %{name: "New Zealand", country_code: "NZ"}

  # Before anyone's employment starts, so a person's own dates are what bound their entitlement.
  @policy_from ~D[2024-01-01]

  # A leave type's unit is what every amount below it is counted in, and its place in this list is
  # its place in the organisation's own list of types.
  @leave_types [
    {"Annual leave", :hours},
    {"Sick leave", :days},
    {"Quarterly leave", :hours},
    {"Birthday leave", :days},
    {"Longevity leave", :days},
    {"Public holiday allowance", :hours},
    {"Bereavement leave", :days}
  ]

  @annual %{
    leave_type: "Annual leave",
    amount_source: :fixed,
    grant_amount: "200",
    grant_basis: :employment_date,
    grant_period: :year,
    grant_timing: :daily,
    pro_rated_by_fte: true,
    expiry_rule: :never,
    allow_negative: false,
    excess_threshold: "300"
  }

  @sick %{
    leave_type: "Sick leave",
    amount_source: :fixed,
    grant_amount: "20",
    grant_basis: :employment_date,
    grant_period: :year,
    grant_timing: :period_start,
    pro_rated_by_fte: false,
    expiry_rule: :cap,
    rollover_cap: "20",
    allow_negative: false
  }

  @quarterly %{
    leave_type: "Quarterly leave",
    amount_source: :fixed,
    grant_amount: "8",
    grant_basis: :calendar_year,
    grant_period: :quarter,
    grant_timing: :period_start,
    pro_rated_by_fte: true,
    expiry_rule: :grant_period_end,
    allow_negative: false
  }

  @birthday %{
    leave_type: "Birthday leave",
    amount_source: :fixed,
    grant_amount: "1",
    grant_basis: :birthday,
    grant_period: :year,
    grant_timing: :period_start,
    pro_rated_by_fte: false,
    expiry_rule: :window,
    expiry_window_days: 14,
    allow_negative: true
  }

  @longevity %{
    leave_type: "Longevity leave",
    amount_source: :fixed,
    grant_amount: "1",
    grant_basis: :employment_date,
    grant_period: :year,
    grant_timing: :period_start,
    pro_rated_by_fte: false,
    expiry_rule: :grant_period_end,
    allow_negative: false
  }

  # The amount is the calendar's own: the holidays in the person's leave year, at their hours.
  @public_holidays %{
    leave_type: "Public holiday allowance",
    amount_source: :public_holidays,
    grant_basis: :employment_date,
    grant_period: :year,
    grant_timing: :period_start,
    pro_rated_by_fte: true,
    expiry_rule: :never,
    allow_negative: false
  }

  @bereavement %{
    leave_type: "Bereavement leave",
    amount_source: :none,
    pro_rated_by_fte: false,
    expiry_rule: :never,
    allow_negative: true
  }

  @policies [
    %{
      name: "New Zealand employee",
      entitlements: [@annual, @sick, @quarterly, @birthday, @longevity, @bereavement]
    },
    %{
      name: "New Zealand contractor",
      entitlements: [@annual, @public_holidays, @bereavement]
    }
  ]

  @people [
    %{
      name: "Mog",
      email: "mog@example.test",
      role: :admin,
      employment_start_date: ~D[2024-12-15],
      birth_date: ~D[1990-08-10],
      policy: "New Zealand employee",
      # 36 hours against a 40 hour week: 0.9 FTE.
      work_pattern: %{
        monday_hours: "9",
        tuesday_hours: "9",
        wednesday_hours: "9",
        thursday_hours: "0",
        friday_hours: "9",
        saturday_hours: "0",
        sunday_hours: "0"
      }
    },
    %{
      name: "Ari Kelburn",
      email: "ari@example.test",
      role: :member,
      employment_start_date: ~D[2025-01-01],
      birth_date: ~D[1985-03-22],
      policy: "New Zealand contractor",
      # 20 hours: 0.5 FTE.
      work_pattern: %{
        monday_hours: "4",
        tuesday_hours: "4",
        wednesday_hours: "4",
        thursday_hours: "4",
        friday_hours: "4",
        saturday_hours: "0",
        sunday_hours: "0"
      }
    }
  ]

  # New Zealand's national public holidays, on the dates they are observed rather than the dates
  # they fall — a Saturday holiday is taken on the following Monday. Regional anniversary days are
  # not here; an organisation with staff outside one region would hold a calendar per region.
  @public_holiday_dates [
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
  Builds the whole example, returning what it made by name.

  Raises on anything that will not validate. Expects an empty database — the caller checks that.
  """
  @spec run() :: %{
          organisation: Organisation.t(),
          policies: %{String.t() => LeavePolicy.t()},
          people: %{String.t() => Person.t()}
        }
  def run do
    organisation = add_organisation()
    calendar = add_calendar(organisation)
    leave_types = add_leave_types(organisation)
    policies = Map.new(@policies, &{&1.name, add_policy(organisation, &1, leave_types)})
    people = Map.new(@people, &{&1.name, add_person(organisation, policies, calendar, &1)})

    %{organisation: organisation, policies: policies, people: people}
  end

  defp add_organisation do
    {:ok, organisation} = Org.create_organisation(@system, @organisation)

    organisation
  end

  defp add_calendar(organisation) do
    {:ok, calendar} = Org.create_holiday_calendar(organisation, @system, @calendar)

    Enum.each(@public_holiday_dates, fn {date, name} ->
      {:ok, _holiday} = Org.create_public_holiday(calendar, @system, %{date: date, name: name})
    end)

    calendar
  end

  defp add_leave_types(organisation) do
    @leave_types
    |> Enum.with_index(1)
    |> Map.new(fn {{name, unit}, position} ->
      {:ok, leave_type} =
        Policies.create_leave_type(organisation, @system, %{
          name: name,
          unit: unit,
          position: position
        })

      {name, leave_type}
    end)
  end

  defp add_policy(organisation, attrs, leave_types) do
    {:ok, policy} = Policies.create_leave_policy(organisation, @system, %{name: attrs.name})

    Enum.each(attrs.entitlements, &add_entitlement(policy, leave_types, &1))

    policy
  end

  defp add_entitlement(policy, leave_types, entitlement) do
    leave_type = Map.fetch!(leave_types, entitlement.leave_type)

    attrs =
      entitlement |> Map.delete(:leave_type) |> Map.put(:effective_from, @policy_from)

    {:ok, _entitlement} = Policies.create_entitlement(policy, leave_type, @system, attrs)
  end

  defp add_person(organisation, policies, calendar, attrs) do
    started_on = attrs.employment_start_date

    {:ok, person} =
      People.create_person(organisation, @system, Map.drop(attrs, [:policy, :work_pattern]))

    {:ok, _pattern} =
      People.create_work_pattern(
        person,
        @system,
        Map.put(attrs.work_pattern, :effective_from, started_on)
      )

    {:ok, _assignment} =
      People.create_policy_assignment(person, @system, %{
        leave_policy_id: Map.fetch!(policies, attrs.policy).id,
        effective_from: started_on
      })

    {:ok, _assignment} =
      People.create_calendar_assignment(person, @system, %{
        holiday_calendar_id: calendar.id,
        effective_from: started_on
      })

    person
  end
end
