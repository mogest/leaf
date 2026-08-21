defmodule Leaf.People.WorkPattern do
  @moduledoc """
  The hours a person works on each day of the week.

  Applies from `effective_from` until the next pattern supersedes it. Contracted weekly hours and
  FTE are derived from it, never stored.
  """

  use Leaf.Schema

  alias Leaf.People.Person

  @type t :: %__MODULE__{}

  @hour_fields [
    :monday_hours,
    :tuesday_hours,
    :wednesday_hours,
    :thursday_hours,
    :friday_hours,
    :saturday_hours,
    :sunday_hours
  ]

  @fields [:person_id, :effective_from | @hour_fields]

  schema "work_patterns" do
    field :effective_from, :date
    field :monday_hours, :decimal
    field :tuesday_hours, :decimal
    field :wednesday_hours, :decimal
    field :thursday_hours, :decimal
    field :friday_hours, :decimal
    field :saturday_hours, :decimal
    field :sunday_hours, :decimal

    belongs_to :person, Person

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(pattern, attrs) do
    pattern
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_hours()
    |> assoc_constraint(:person)
    |> unique_constraint([:person_id, :effective_from])
  end

  defp validate_hours(changeset) do
    Enum.reduce(@hour_fields, changeset, &validate_number(&2, &1, greater_than_or_equal_to: 0))
  end
end
