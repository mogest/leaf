defmodule Leaf.People.PersonHolidayCalendar do
  @moduledoc "The holiday calendar a person observes, from `effective_from` until superseded."

  use Leaf.Schema

  alias Leaf.Org.HolidayCalendar
  alias Leaf.People.Person

  @type t :: %__MODULE__{}

  @fields [:person_id, :holiday_calendar_id, :effective_from]

  schema "person_holiday_calendars" do
    field :effective_from, :date

    belongs_to :person, Person
    belongs_to :holiday_calendar, HolidayCalendar

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> assoc_constraint(:person)
    |> assoc_constraint(:holiday_calendar)
    |> unique_constraint([:person_id, :effective_from])
  end
end
