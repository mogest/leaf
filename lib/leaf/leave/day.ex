defmodule Leaf.Leave.Day do
  @moduledoc """
  One date's worth of one leave type within a request.

  This is the unit a day off is split into, so a single date can draw on more than one leave type.

  An amount is held in the unit it was asked for, not in the leave type's. "The whole of Tuesday
  off" is a fact about the work pattern on that Tuesday, so converting it when the request is
  filed would freeze an hours figure the person never chose: drop to a seven-hour day before the
  date and a day off is seven hours. `in_unit/3` does the conversion instead, on the hours worked
  on the date, every time it is asked for.

  `hours_in_day` is not stored for the same reason. It is here only so that a date the person does
  not work — one off their pattern, or a public holiday their policy grants them off — is refused
  where it happens, against the date it happened on. A date nobody knows the hours of is refused
  with it: a hole in the record is not a day off, and leave filed into one cannot be measured.

  Leave dated before a person's first work pattern is therefore filed by recording a pattern that
  reaches back over it, which is how a sick day found after go-live is entered (§4.10). Removing
  that pattern afterwards leaves the day with no hours on record, which `Leaf.Ledger.ready?/2`
  answers for.
  """

  use Leaf.Schema

  alias Leaf.Leave.Request
  alias Leaf.Policies.LeaveType

  @type t :: %__MODULE__{}
  @type unit :: :hours | :days

  @none Decimal.new(0)

  @units [:hours, :days]

  @fields [:leave_type_id, :date, :amount, :unit, :hours_in_day]

  @required [:leave_type_id, :date, :amount, :unit]

  schema "leave_days" do
    field :date, :date
    field :amount, :decimal
    field :unit, Ecto.Enum, values: @units
    field :hours_in_day, :decimal, virtual: true

    belongs_to :leave_request, Request
    belongs_to :leave_type, LeaveType

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(day, attrs) do
    day
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> as_stored(:amount, greater_than: 0)
    |> validate_working_day()
    |> assoc_constraint(:leave_request)
    |> assoc_constraint(:leave_type)
    |> unique_constraint([:leave_request_id, :date, :leave_type_id], error_key: :date)
  end

  @doc """
  What the day is worth in `unit`, given the hours its person works on its date.

  A date worth no hours — a public holiday their policy grants them off, or a pattern since
  corrected to none — is worth nothing in either unit, whichever it was asked for in. The figure is
  exact: it is rounded where it is stored or shown and never on the way there.
  """
  @spec in_unit(t(), unit(), Decimal.t()) :: Decimal.t()
  def in_unit(day, unit, hours), do: worth(day, unit, hours, Decimal.positive?(hours))

  defp worth(_day, _unit, _hours, false), do: @none
  defp worth(%{unit: unit} = day, unit, _hours, true), do: day.amount
  defp worth(%{unit: :days} = day, :hours, hours, true), do: Decimal.mult(day.amount, hours)
  defp worth(%{unit: :hours} = day, :days, hours, true), do: Decimal.div(day.amount, hours)

  defp validate_working_day(changeset) do
    known(changeset, get_field(changeset, :hours_in_day))
  end

  defp known(changeset, nil),
    do: add_error(changeset, :date, "is before the first work pattern on record")

  defp known(changeset, hours), do: worked(changeset, Decimal.positive?(hours))

  defp worked(changeset, true), do: changeset
  defp worked(changeset, false), do: add_error(changeset, :date, "is not a working day")
end
