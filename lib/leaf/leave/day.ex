defmodule Leaf.Leave.Day do
  @moduledoc """
  One date's worth of one leave type within a request.

  This is the unit a day off is split into, so a single date can draw on more than one leave type.

  An amount is held in the unit it was asked for, not in the leave type's. "The whole of Tuesday
  off" is a fact about the work pattern on that Tuesday, so converting it when the request is
  filed would freeze an hours figure the person never chose: drop to a seven-hour day before the
  date and a day off is seven hours. `in_unit/3` does the conversion instead, on the hours worked
  on the date, every time it is asked for.

  `hours_in_day` is not stored for the same reason. It is here only so that filing leave on a day
  the person does not work is refused where it happens, against the date it happened on.
  """

  use Leaf.Schema

  alias Leaf.Leave.Request
  alias Leaf.Policies.LeaveType

  @type t :: %__MODULE__{}
  @type unit :: :hours | :days

  @units [:hours, :days]

  @fields [:leave_type_id, :date, :amount, :unit, :hours_in_day]

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
    |> validate_required(@fields)
    |> validate_number(:amount, greater_than: 0)
    |> validate_working_day()
    |> assoc_constraint(:leave_request)
    |> assoc_constraint(:leave_type)
  end

  @doc """
  What the day is worth in `unit`, given the hours its person works on its date.

  `hours_in_day` is unread where the day is already in the unit asked for, which is most of them,
  so a caller with nothing to convert need not go and find it.
  """
  @spec in_unit(t(), unit(), Decimal.t() | nil) :: Decimal.t()
  def in_unit(%{unit: unit} = day, unit, _hours_in_day), do: day.amount
  def in_unit(%{unit: :days} = day, :hours, hours), do: round2(Decimal.mult(day.amount, hours))
  def in_unit(%{unit: :hours} = day, :days, hours), do: round2(Decimal.div(day.amount, hours))

  defp round2(amount), do: Decimal.round(amount, 2)

  defp validate_working_day(changeset) do
    case get_field(changeset, :hours_in_day) do
      nil -> changeset
      hours -> worked(changeset, Decimal.positive?(hours))
    end
  end

  defp worked(changeset, true), do: changeset
  defp worked(changeset, false), do: add_error(changeset, :date, "is not a working day")
end
