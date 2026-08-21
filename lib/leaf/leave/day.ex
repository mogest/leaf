defmodule Leaf.Leave.Day do
  @moduledoc """
  One date's worth of one leave type within a request.

  This is the unit a day off is split into, so a single date can draw on more than one leave type.

  `hours` and `days` are both stored, converted through the person's work pattern as it stood when
  the leave was recorded, so a later pattern correction cannot rewrite what was taken.
  """

  use Leaf.Schema

  alias Leaf.Leave.Request
  alias Leaf.Policies.LeaveType

  @type t :: %__MODULE__{}

  @fields [:leave_request_id, :leave_type_id, :date, :hours, :days]

  schema "leave_days" do
    field :date, :date
    field :hours, :decimal
    field :days, :decimal

    belongs_to :leave_request, Request
    belongs_to :leave_type, LeaveType

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(day, attrs) do
    day
    |> cast(attrs, @fields)
    |> validate_required([:leave_type_id, :date, :hours, :days])
    |> validate_number(:hours, greater_than_or_equal_to: 0)
    |> validate_number(:days, greater_than_or_equal_to: 0)
    |> assoc_constraint(:leave_request)
    |> assoc_constraint(:leave_type)
  end
end
