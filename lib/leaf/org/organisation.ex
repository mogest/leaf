defmodule Leaf.Org.Organisation do
  @moduledoc "The organisation that owns the people, policies, leave types and holiday calendars."

  use Leaf.Schema

  @type t :: %__MODULE__{}

  @fields [:name, :full_time_week_hours, :standard_day_hours, :year_start_month]

  schema "organisations" do
    field :name, :string
    field :full_time_week_hours, :decimal
    field :standard_day_hours, :decimal
    field :year_start_month, :integer

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(organisation, attrs) do
    organisation
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:full_time_week_hours, greater_than: 0)
    |> validate_number(:standard_day_hours, greater_than: 0)
    |> validate_inclusion(:year_start_month, 1..12)
  end
end
