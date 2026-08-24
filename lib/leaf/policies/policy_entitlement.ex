defmodule Leaf.Policies.PolicyEntitlement do
  @moduledoc """
  What one policy grants for one leave type over one span of time.

  `effective_to` ends the entitlement's life — the last date leave of this type may be taken.
  `granted_to` narrows the grant window inside that life, so an entitlement can stop granting
  while a remaining balance stays spendable. Both are inclusive, and null on either means
  open-ended. Offering is intermittent, which is why this carries an end date rather than relying
  on a successor row.

  `grant_amount` is per `grant_period`, at 1.0 FTE, in the leave type's unit.

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
    :expiry_window_days | @grant_fields
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

    belongs_to :leave_policy, LeavePolicy
    belongs_to :leave_type, LeaveType

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entitlement, attrs) do
    entitlement
    |> cast(attrs, @fields)
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
    |> validate_number(:grant_amount, greater_than_or_equal_to: 0)
    |> validate_number(:rollover_cap, greater_than_or_equal_to: 0)
    |> validate_number(:expiry_window_days, greater_than: 0)
    |> validate_storable(:grant_amount)
    |> validate_storable(:rollover_cap)
    |> validate_storable(:expiry_window_days)
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

  defp validate_amount_source(changeset) do
    validate_amount_source(changeset, get_field(changeset, :amount_source))
  end

  defp validate_amount_source(changeset, :fixed) do
    changeset
    |> validate_required(@grant_fields)
    |> validate_grant_period(get_field(changeset, :grant_basis))
  end

  defp validate_amount_source(changeset, :public_holidays) do
    basis = get_field(changeset, :grant_basis)

    changeset
    |> validate_absent([:grant_amount])
    |> validate_required([:grant_basis, :grant_period, :grant_timing])
    |> validate_grant_period(basis)
    |> validate_allowance_timing(basis)
  end

  defp validate_amount_source(changeset, :none), do: validate_absent(changeset, @grant_fields)
  defp validate_amount_source(changeset, nil), do: changeset

  defp validate_grant_period(changeset, :birthday),
    do: validate_inclusion(changeset, :grant_period, [:year])

  defp validate_grant_period(changeset, _basis), do: changeset

  # A block grant is skipped where its period opened before the person was covered, which is a
  # deliberate gap for a fixed amount but a wrong count for one measured off the calendar: a
  # mid-period joiner would be credited none of the holidays they go on to observe. Anchored to
  # anything but their own start date, the allowance therefore has to be counted as it falls.
  defp validate_allowance_timing(changeset, :employment_date), do: changeset

  defp validate_allowance_timing(changeset, _basis) do
    validate_inclusion(changeset, :grant_timing, [:daily])
  end

  defp validate_expiry_rule(changeset) do
    validate_expiry_rule(changeset, get_field(changeset, :expiry_rule))
  end

  defp validate_expiry_rule(changeset, :cap) do
    changeset
    |> validate_required([:rollover_cap])
    |> validate_absent([:expiry_window_days])
  end

  defp validate_expiry_rule(changeset, :window) do
    changeset
    |> validate_required([:expiry_window_days])
    |> validate_absent([:rollover_cap])
  end

  defp validate_expiry_rule(changeset, _rule) do
    validate_absent(changeset, [:rollover_cap, :expiry_window_days])
  end
end
