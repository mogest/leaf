defmodule Leaf.Leave.LedgerEntry do
  @moduledoc """
  One movement of one balance.

  An opening import, an accrual, a grant, an expiry or a manual adjustment. Consumption is not
  here — approved `Leaf.Leave.Day` rows are the record of leave taken, so a balance is these
  entries less those days.

  `accrual`, `grant` and `expiry` entries are derived and regenerated wholesale when history is
  corrected; `opening_balance` and `adjustment` are written by hand and never touched.
  """

  use Leaf.Schema

  alias Leaf.People.Person
  alias Leaf.Policies.LeaveType

  @type t :: %__MODULE__{}

  @kinds [:opening_balance, :accrual, :grant, :expiry, :adjustment]

  @fields [
    :person_id,
    :leave_type_id,
    :source_entry_id,
    :created_by_id,
    :date,
    :kind,
    :amount,
    :expires_on,
    :reason
  ]

  schema "leave_ledger_entries" do
    field :date, :date
    field :kind, Ecto.Enum, values: @kinds
    field :amount, :decimal
    field :expires_on, :date
    field :reason, :string

    belongs_to :person, Person
    belongs_to :leave_type, LeaveType
    belongs_to :source_entry, __MODULE__
    belongs_to :created_by, Person

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @fields)
    |> validate_required([:person_id, :leave_type_id, :date, :kind, :amount])
    |> validate_kind()
    |> validate_date_order(:date, :expires_on)
    |> assoc_constraint(:person)
    |> assoc_constraint(:leave_type)
    |> assoc_constraint(:source_entry)
    |> assoc_constraint(:created_by)
  end

  defp validate_kind(changeset), do: validate_kind(changeset, get_field(changeset, :kind))

  defp validate_kind(changeset, :expiry), do: validate_absent(changeset, [:expires_on])

  defp validate_kind(changeset, :adjustment) do
    changeset
    |> validate_required([:reason])
    |> validate_absent([:source_entry_id])
  end

  defp validate_kind(changeset, _kind), do: validate_absent(changeset, [:source_entry_id])
end
