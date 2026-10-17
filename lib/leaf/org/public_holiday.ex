defmodule Leaf.Org.PublicHoliday do
  @moduledoc """
  One public holiday on one calendar.

  `date` is the day it falls on. `observed_on` is the weekday it moves to for anybody who would not
  otherwise work that day (NZ Holidays Act ss 45, 45A), and is empty for a holiday that never moves.
  """

  use Leaf.Schema

  alias Leaf.Org.Calendar

  @type t :: %__MODULE__{}

  schema "public_holidays" do
    field :date, :date
    field :observed_on, :date
    field :name, :string

    belongs_to :calendar, Calendar

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(holiday, attrs) do
    holiday
    |> cast(attrs, [:date, :observed_on, :name])
    |> validate_required([:calendar_id, :date, :name])
    |> validate_observed_on()
    |> assoc_constraint(:calendar)
    |> unique_constraint([:calendar_id, :date], error_key: :date)
  end

  defp validate_observed_on(changeset) do
    validate_change(changeset, :observed_on, fn :observed_on, observed_on ->
      moved(get_field(changeset, :date), observed_on)
    end)
  end

  defp moved(nil, _observed_on), do: []

  defp moved(date, observed_on),
    do: errors(Date.day_of_week(date), Date.after?(observed_on, date))

  defp errors(weekday, _later?) when weekday < 6,
    do: [observed_on: "is only for a holiday on a weekend"]

  defp errors(_weekend, true), do: []
  defp errors(_weekend, false), do: [observed_on: "must be after the day it falls on"]
end
