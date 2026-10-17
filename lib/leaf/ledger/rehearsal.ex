defmodule Leaf.Ledger.Rehearsal do
  @moduledoc """
  One sample person's balance under an entitlement, month by month for three years.

  The sample people are written onto the entitlement's policy and the balance is worked out by the
  ledger as it would be for anybody, so what a rehearsal shows is what the entitlement will do
  rather than a second account of it. The caller rolls everything back.

  None of them take leave, bar the one away on leave that suspends accrual: a balance left alone is
  the one that shows where a cap or a lapse bites.
  """

  alias Leaf.Leave.Day
  alias Leaf.Ledger
  alias Leaf.Ledger.Movement
  alias Leaf.Org
  alias Leaf.Org.Organisation
  alias Leaf.People
  alias Leaf.Policies
  alias Leaf.Policies.LeavePolicy
  alias Leaf.Policies.PolicyEntitlement

  @type t :: %__MODULE__{
          name: String.t(),
          balances: [{Date.t(), Decimal.t()}],
          losses: [Movement.t()]
        }

  @enforce_keys [:name, :balances, :losses]
  defstruct [:name, :balances, :losses]

  @months 36
  @away_after_months 6
  @away_weeks 12
  @three_days [:monday, :tuesday, :wednesday]
  @weekdays [:monday, :tuesday, :wednesday, :thursday, :friday]
  @days [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  @doc "A rehearsal for each sample person, joining from the first day the entitlement is tracked."
  @spec all(Organisation.t(), LeavePolicy.t(), PolicyEntitlement.t()) :: [t()]
  def all(organisation, policy, entitlement) do
    {joined, _last} = dates(organisation, entitlement.effective_from)

    for {name, worked, away} <- samples(organisation.id) do
      person = sample(organisation, policy, joined, worked)
      rehearsed(name, person, joined, away_days(away, joined), entitlement.leave_type_id)
    end
  end

  @doc "The first and last dates a rehearsal of an entitlement offered from `effective_from` reads."
  @spec dates(Organisation.t(), Date.t()) :: {Date.t(), Date.t()}
  def dates(organisation, effective_from) do
    joined = Enum.max([effective_from, organisation.tracked_from], Date)

    {joined, Date.shift(joined, month: @months)}
  end

  @doc "The names of the sample people `all/3` rehearses, in its order."
  @spec names(Ecto.UUID.t()) :: [String.t()]
  def names(organisation_id), do: Enum.map(samples(organisation_id), &elem(&1, 0))

  # Each with the days they work, and the leave that suspends accrual they are away on, if any: the
  # organisation's first such type, where it has one.
  defp samples(organisation_id) do
    regular = [{"Full time", @weekdays, nil}, {"Three days a week", @three_days, nil}]

    case Enum.find(Policies.leave_types_offered(organisation_id), & &1.suspends_accrual) do
      nil ->
        regular

      away ->
        regular ++
          [{"Full time, #{@away_weeks} weeks' #{String.downcase(away.name)}", @weekdays, away}]
    end
  end

  defp away_days(nil, _joined), do: []

  defp away_days(leave_type, joined) do
    from = Date.shift(joined, month: @away_after_months)

    for date <- Date.range(from, Date.add(from, @away_weeks * 7 - 1)),
        Date.day_of_week(date) <= 5,
        do: %Day{leave_type_id: leave_type.id, date: date, amount: Decimal.new(1), unit: :days}
  end

  # Born so that a birthday, for an entitlement reckoned from one, falls half way through the first year.
  defp sample(organisation, policy, joined, worked) do
    attrs = %{
      name: "Sample",
      email: "sample-#{Ecto.UUID.generate()}@example.invalid",
      role: :member,
      employment_start_date: joined,
      birth_date: Date.shift(joined, year: -30, month: 6)
    }

    {:ok, person} = People.create_person(organisation, nil, attrs)
    day = Decimal.div(organisation.full_time_week_hours, 5)

    hours =
      Map.new(@days, &{:"#{&1}_hours", if(&1 in worked, do: day, else: Decimal.new(0))})

    {:ok, _pattern} =
      People.create_work_pattern(person, nil, Map.put(hours, :effective_from, joined))

    {:ok, _assignment} =
      People.create_policy_assignment(person, nil, %{
        leave_policy_id: policy.id,
        effective_from: joined
      })

    case Org.countries(organisation.id) do
      [country | _others] ->
        attrs = %{calendar_id: country.id, effective_from: joined}
        {:ok, _assignment} = People.create_calendar_assignment(person, nil, attrs)

      [] ->
        nil
    end

    person
  end

  defp rehearsed(name, person, joined, away, type) do
    statements =
      for month <- 0..@months do
        as_at = Date.shift(joined, month: month)
        {as_at, statement(person, as_at, Enum.reject(away, &Date.after?(&1.date, as_at)), type)}
      end

    {_as_at, last} = List.last(statements)

    %__MODULE__{
      name: name,
      balances: for({as_at, statement} <- statements, do: {as_at, balance(statement)}),
      losses: losses(last)
    }
  end

  defp statement(person, as_at, away, type) do
    person |> Ledger.statements(as_at, away) |> Enum.find(&(&1.leave_type.id == type))
  end

  defp balance(nil), do: Decimal.new(0)
  defp balance(statement), do: statement.balance

  defp losses(nil), do: []

  defp losses(statement),
    do: Enum.filter(statement.movements, &(&1.kind in [:expiry, :rollover_cap]))
end
