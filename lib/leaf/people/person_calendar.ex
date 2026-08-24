defmodule Leaf.People.PersonCalendar do
  @moduledoc "The calendar a person is on, from `effective_from` until superseded."

  use Leaf.Schema

  alias Leaf.Org.Calendar
  alias Leaf.People.Person

  @type t :: %__MODULE__{}

  @fields [:calendar_id, :effective_from]

  schema "person_calendars" do
    field :effective_from, :date

    belongs_to :person, Person
    belongs_to :calendar, Calendar

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, @fields)
    |> validate_required([:person_id | @fields])
    |> assoc_constraint(:person)
    |> assoc_constraint(:calendar)
    |> unique_constraint([:person_id, :effective_from])
  end
end
