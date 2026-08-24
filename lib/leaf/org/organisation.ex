defmodule Leaf.Org.Organisation do
  @moduledoc """
  The organisation that owns the people, policies, leave types and holiday calendars.

  `tracked_from` is the date leave started being tracked here. Nothing accrues, is granted or
  expires before it — the opening balances account for everything up to it — so it is the floor
  under every derived figure. Leave dated earlier still counts, and draws down what was brought in.
  """

  use Leaf.Schema

  @type t :: %__MODULE__{}

  @fields [:name, :full_time_week_hours, :standard_day_hours, :year_start_month, :tracked_from]

  schema "organisations" do
    field :name, :string
    field :full_time_week_hours, :decimal
    field :standard_day_hours, :decimal
    field :year_start_month, :integer
    field :tracked_from, :date

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(organisation, attrs) do
    organisation
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:full_time_week_hours, greater_than: 0, less_than_or_equal_to: 168)
    |> validate_number(:standard_day_hours, greater_than: 0, less_than_or_equal_to: 24)
    |> validate_inclusion(:year_start_month, 1..12)
  end
end
