defmodule Leaf.Policies.PolicyEntitlement do
  @moduledoc """
  What one policy grants for one leave type over one span of time.

  `effective_to` ends the entitlement's life — the last date leave of this type may be taken.
  `granted_to` narrows the grant window inside that life, so an entitlement can stop granting
  while a remaining balance stays spendable. Both are inclusive, and null on either means
  open-ended. Offering is intermittent, which is why this carries an end date rather than relying
  on a successor row.

  `grant_amount` is per `grant_period`, at 1.0 FTE, in the leave type's unit.

  `qualifying_months` is service before a fixed amount aligned to the start date grants anything,
  and its cycle runs from the date that service is reached: NZ sick leave is 10 days after six
  months, then every 12 months from there. `takeable_after_months` is service before leave of the
  type may be taken at all, so NZ bereavement leave waits six months, and sick leave may or may not
  be taken in advance of its first grant as the organisation chooses.

  Two grant windows for one leave type under one policy may not overlap: the balance would be
  granted twice over. Changing the terms therefore means closing the old row with `granted_to` and
  opening the next the day after — their lives may overlap, and it is closing with `effective_to`
  that lapses what the old row granted, which is a discontinuation rather than a change of terms.
  """

  use Leaf.Schema

  alias Leaf.Policies.LeavePolicy
  alias Leaf.Policies.LeaveType

  @type t :: %__MODULE__{}

  @amount_sources [:fixed, :public_holidays, :none]
  @grant_bases [:employment_date, :birthday, :calendar_year, :organisation_year]
  @grant_periods [:month, :quarter, :year]
  @grant_timings [:daily, :period_start]
  @expiry_rules [:never, :cap, :grant_period_end, :window]

  @grant_fields [:grant_amount, :grant_basis, :grant_period, :grant_timing]

  @fields [
    :effective_from,
    :effective_to,
    :granted_to,
    :amount_source,
    :pro_rated_by_fte,
    :expiry_rule,
    :rollover_cap,
    :expiry_window_days,
    :suspension_allowance_weeks,
    :qualifying_months,
    :takeable_after_months | @grant_fields
  ]

  schema "policy_entitlements" do
    field :effective_from, :date
    field :effective_to, :date
    field :granted_to, :date
    field :amount_source, Ecto.Enum, values: @amount_sources
    field :grant_amount, :decimal
    field :grant_basis, Ecto.Enum, values: @grant_bases
    field :grant_period, Ecto.Enum, values: @grant_periods
    field :grant_timing, Ecto.Enum, values: @grant_timings
    field :pro_rated_by_fte, :boolean
    field :expiry_rule, Ecto.Enum, values: @expiry_rules
    field :rollover_cap, :decimal
    field :expiry_window_days, :integer
    field :suspension_allowance_weeks, :decimal
    field :qualifying_months, :integer
    field :takeable_after_months, :integer

    belongs_to :leave_policy, LeavePolicy
    belongs_to :leave_type, LeaveType

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entitlement, attrs) do
    entitlement
    |> cast(attrs, @fields)
    |> settled()
    |> validate_required([
      :leave_policy_id,
      :leave_type_id,
      :effective_from,
      :amount_source,
      :pro_rated_by_fte,
      :expiry_rule
    ])
    |> validate_amount_source()
    |> validate_expiry_rule()
    |> as_stored(:grant_amount, greater_than_or_equal_to: 0)
    |> as_stored(:rollover_cap, greater_than_or_equal_to: 0)
    |> as_stored(:expiry_window_days, greater_than: 0)
    |> as_stored(:suspension_allowance_weeks, greater_than: 0)
    |> as_stored(:qualifying_months, greater_than: 0, less_than_or_equal_to: 12)
    |> as_stored(:takeable_after_months, greater_than: 0, less_than_or_equal_to: 12)
    |> validate_date_order(:effective_from, :granted_to)
    |> validate_date_order(:effective_from, :effective_to)
    |> validate_date_order(:granted_to, :effective_to)
    |> assoc_constraint(:leave_policy)
    |> assoc_constraint(:leave_type)
    |> exclusion_constraint(:effective_from,
      name: :policy_entitlements_no_overlap,
      message: "overlaps another entitlement for this leave type"
    )
  end

  # What one choice rules out is cleared rather than refused, so a form need only offer what
  # applies, and a field it stops offering is emptied rather than left behind.
  defp settled(changeset) do
    changeset
    |> settle_source(get_field(changeset, :amount_source))
    |> settle_period()
    |> settle_timing()
    |> settle_expiry_rule()
    |> settle_suspension_allowance()
    |> settle_qualifying()
  end

  defp settle_source(changeset, :none) do
    changeset
    |> clear(@grant_fields)
    |> put_change(:pro_rated_by_fte, false)
    |> put_change(:expiry_rule, :never)
  end

  defp settle_source(changeset, :public_holidays), do: clear(changeset, [:grant_amount])
  defp settle_source(changeset, _source), do: changeset

  defp settle_period(changeset) do
    case get_field(changeset, :grant_basis) do
      :birthday -> put_change(changeset, :grant_period, :year)
      _basis -> changeset
    end
  end

  # A block grant is skipped where its period opened before the person was covered, which is a
  # deliberate gap for a fixed amount but a wrong count for one measured off the calendar: a
  # mid-period joiner would be credited none of the holidays they go on to observe. Anchored to
  # anything but their own start date, the allowance therefore has to be counted as it falls.
  defp settle_timing(changeset) do
    case {get_field(changeset, :amount_source), get_field(changeset, :grant_basis)} do
      {:public_holidays, basis} when basis != :employment_date ->
        put_change(changeset, :grant_timing, :daily)

      _terms ->
        changeset
    end
  end

  defp settle_expiry_rule(changeset) do
    case get_field(changeset, :expiry_rule) do
      :cap -> clear(changeset, [:expiry_window_days])
      :window -> clear(changeset, [:rollover_cap])
      _rule -> clear(changeset, [:rollover_cap, :expiry_window_days])
    end
  end

  defp settle_suspension_allowance(changeset) do
    case {get_field(changeset, :amount_source), get_field(changeset, :grant_timing)} do
      {:fixed, :daily} -> changeset
      _terms -> clear(changeset, [:suspension_allowance_weeks])
    end
  end

  defp settle_qualifying(changeset) do
    case {get_field(changeset, :amount_source), get_field(changeset, :grant_basis)} do
      {:fixed, :employment_date} -> changeset
      _terms -> clear(changeset, [:qualifying_months])
    end
  end

  defp validate_amount_source(changeset) do
    case get_field(changeset, :amount_source) do
      :fixed ->
        validate_required(changeset, @grant_fields)

      :public_holidays ->
        validate_required(changeset, [:grant_basis, :grant_period, :grant_timing])

      _source ->
        changeset
    end
  end

  defp validate_expiry_rule(changeset) do
    case get_field(changeset, :expiry_rule) do
      :cap -> validate_required(changeset, [:rollover_cap])
      :window -> validate_required(changeset, [:expiry_window_days])
      _rule -> changeset
    end
  end
end
