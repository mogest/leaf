defmodule Leaf.Policies.LeaveType do
  @moduledoc """
  A kind of leave the organisation offers.

  `unit` is the unit of the balance, inherited by every amount that measures it. Grant and expiry
  behaviour belongs to the policy, not here — the same type behaves differently under two
  policies.
  """

  use Leaf.Schema

  alias Leaf.Org.Organisation

  @type t :: %__MODULE__{}

  @units [:hours, :days]

  @fields [:name, :unit, :position, :archived_at]

  schema "leave_types" do
    field :name, :string
    field :unit, Ecto.Enum, values: @units
    field :position, :integer
    field :archived_at, :utc_datetime

    belongs_to :organisation, Organisation

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(leave_type, attrs) do
    leave_type
    |> cast(attrs, @fields)
    |> validate_required([:organisation_id, :name, :unit, :position])
    |> assoc_constraint(:organisation)
  end
end
