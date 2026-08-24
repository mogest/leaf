defmodule Leaf.Leave.BalanceEntry do
  @moduledoc """
  A balance figure entered by hand: an opening import or an adjustment.

  Accruals, grants and expiries are not here. They follow from a person's dates, work patterns,
  policy and leave taken, so they are worked out on demand rather than recorded — correcting an
  input corrects every balance that depended on it, with nothing to invalidate. These two kinds
  are the only movements no configuration can account for, so they are the only ones stored.

  `expires_on` gives an entry a lapse date of its own, which an import needs: a quarterly balance
  carried in at go-live lapses at the end of the quarter it lands in.
  """

  use Leaf.Schema

  alias Leaf.People.Person
  alias Leaf.Policies.LeaveType

  @type t :: %__MODULE__{}

  @kinds [:opening_balance, :adjustment]

  @fields [:leave_type_id, :date, :kind, :amount, :expires_on, :reason]

  schema "leave_balance_entries" do
    field :date, :date
    field :kind, Ecto.Enum, values: @kinds
    field :amount, :decimal
    field :expires_on, :date
    field :reason, :string

    belongs_to :person, Person
    belongs_to :leave_type, LeaveType
    belongs_to :created_by, Person

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @fields)
    |> validate_required([:person_id, :leave_type_id, :date, :kind, :amount])
    |> as_stored(:amount)
    |> validate_reason()
    |> validate_date_order(:date, :expires_on)
    |> assoc_constraint(:person)
    |> assoc_constraint(:leave_type)
    |> assoc_constraint(:created_by)
  end

  defp validate_reason(changeset), do: validate_reason(changeset, get_field(changeset, :kind))
  defp validate_reason(changeset, :adjustment), do: validate_required(changeset, [:reason])
  defp validate_reason(changeset, _kind), do: changeset
end
