defmodule Leaf.Policies.LeaveType do
  @moduledoc """
  A kind of leave the organisation offers.

  `unit` is the unit of the balance, inherited by every amount that measures it. Grant and expiry
  behaviour belongs to the policy, not here — the same type behaves differently under two
  policies.

  `suspends_accrual` is what the leave is rather than how a policy grants it: time on it counts as
  not worked, so daily accrual shrinks over it (§4.7).

  `payroll_code` is what the payroll system calls the type. Leave of a type without one is not
  exported to it.
  """

  use Leaf.Schema

  alias Leaf.Org.Organisation

  @type t :: %__MODULE__{}

  @units [:hours, :days]

  @fields [:name, :unit, :suspends_accrual, :position, :payroll_code, :archived_at]

  schema "leave_types" do
    field :name, :string
    field :unit, Ecto.Enum, values: @units
    field :suspends_accrual, :boolean, default: false
    field :position, :integer
    field :payroll_code, :string
    field :archived_at, :utc_datetime

    belongs_to :organisation, Organisation

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(leave_type, attrs) do
    leave_type
    |> cast(attrs, @fields)
    |> validate_required([:organisation_id, :name, :unit, :suspends_accrual, :position])
    |> as_stored(:position)
    |> assoc_constraint(:organisation)
  end
end
