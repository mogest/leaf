defmodule Leaf.Policies.LeavePolicy do
  @moduledoc """
  A reusable set of entitlements, assigned to people with effective dates.

  Named for the arrangement it describes — "NZ Employee", "Contractor hybrid".

  Public holiday treatment is not stored: holidays are ordinary working days for a person exactly
  when a `public_holidays` entitlement is in force for their policy on that date, and are granted
  off otherwise.
  """

  use Leaf.Schema

  alias Leaf.Org.Organisation
  alias Leaf.Policies.PolicyEntitlement

  @type t :: %__MODULE__{}

  @fields [:name, :archived_at]

  schema "leave_policies" do
    field :name, :string
    field :archived_at, :utc_datetime

    belongs_to :organisation, Organisation
    has_many :entitlements, PolicyEntitlement

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(policy, attrs) do
    policy
    |> cast(attrs, @fields)
    |> validate_required([:organisation_id, :name])
    |> assoc_constraint(:organisation)
  end
end
