defmodule Leaf.People.PersonPolicyAssignment do
  @moduledoc "The leave policy a person is on, from `effective_from` until superseded."

  use Leaf.Schema

  alias Leaf.People.Person
  alias Leaf.Policies.LeavePolicy

  @type t :: %__MODULE__{}

  @fields [:person_id, :leave_policy_id, :effective_from]

  schema "person_policy_assignments" do
    field :effective_from, :date

    belongs_to :person, Person
    belongs_to :leave_policy, LeavePolicy

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> assoc_constraint(:person)
    |> assoc_constraint(:leave_policy)
    |> unique_constraint([:person_id, :effective_from])
  end
end
