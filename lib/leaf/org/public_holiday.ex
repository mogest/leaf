defmodule Leaf.Org.PublicHoliday do
  @moduledoc "One public holiday on one calendar."

  use Leaf.Schema

  alias Leaf.Org.HolidayCalendar

  @type t :: %__MODULE__{}

  @fields [:holiday_calendar_id, :date, :name]

  schema "public_holidays" do
    field :date, :date
    field :name, :string

    belongs_to :holiday_calendar, HolidayCalendar

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(holiday, attrs) do
    holiday
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> assoc_constraint(:holiday_calendar)
  end
end
