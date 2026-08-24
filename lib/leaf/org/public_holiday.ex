defmodule Leaf.Org.PublicHoliday do
  @moduledoc "One public holiday on one calendar."

  use Leaf.Schema

  alias Leaf.Org.Calendar

  @type t :: %__MODULE__{}

  @fields [:date, :name]

  schema "public_holidays" do
    field :date, :date
    field :name, :string

    belongs_to :calendar, Calendar

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(holiday, attrs) do
    holiday
    |> cast(attrs, @fields)
    |> validate_required([:calendar_id | @fields])
    |> assoc_constraint(:calendar)
    |> unique_constraint([:calendar_id, :date])
  end
end
