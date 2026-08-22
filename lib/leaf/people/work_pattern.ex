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

  @fields [:effective_from] ++ @hour_fields

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
    |> validate_required([:person_id | @fields])
    |> validate_hours()
    |> assoc_constraint(:person)
    |> unique_constraint([:person_id, :effective_from])
  end

  @doc "The hours worked over a full week under this pattern."
  @spec weekly_hours(t()) :: Decimal.t()
  def weekly_hours(pattern) do
    @hour_fields |> Enum.map(&Map.fetch!(pattern, &1)) |> Enum.reduce(&Decimal.add/2)
  end

  @doc "The hours worked on `date` under this pattern."
  @spec hours_on(t(), Date.t()) :: Decimal.t()
  def hours_on(pattern, date) do
    Map.fetch!(pattern, Enum.at(@hour_fields, Date.day_of_week(date) - 1))
  end

  @doc "Whether any hours are worked on `date` under this pattern."
  @spec working_day?(t(), Date.t()) :: boolean()
  def working_day?(pattern, date), do: Decimal.positive?(hours_on(pattern, date))

  @doc """
  The fraction of a full-time week this pattern works, for display.

  `full_time_week_hours` is the organisation's, so the same pattern is a different FTE under an
  organisation that counts a full week differently.

  Entitlement arithmetic must not route through this. The division is inexact for most part-time
  weeks, and rounding it here before multiplying loses more than pro-rating an amount in one
  operation does.
  """
  @spec fte(t(), Decimal.t()) :: Decimal.t()
  def fte(pattern, full_time_week_hours) do
    Decimal.div(weekly_hours(pattern), full_time_week_hours)
  end

  defp validate_hours(changeset) do
    Enum.reduce(@hour_fields, changeset, &validate_number(&2, &1, greater_than_or_equal_to: 0))
  end
end
