defmodule Leaf.Org.HolidayCalendar do
  @moduledoc "A named set of public holidays for a country, or a region within one."

  use Leaf.Schema

  alias Leaf.Org.Organisation

  @type t :: %__MODULE__{}

  @fields [:organisation_id, :name, :country_code]

  schema "holiday_calendars" do
    field :name, :string
    field :country_code, :string

    belongs_to :organisation, Organisation

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(calendar, attrs) do
    calendar
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_length(:country_code, is: 2)
    |> assoc_constraint(:organisation)
  end
end
