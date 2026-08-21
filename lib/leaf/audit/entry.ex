defmodule Leaf.Audit.Entry do
  @moduledoc """
  One recorded action, with before and after values in `changes`.

  Deliberately polymorphic — it spans every entity in the system — so the target is identified by
  type and id, not a reference. This is also where a hard-deleted record survives.

  `actor_id` is who acted; `subject_person_id` is whose record it was about, and is the
  only link back to that person once the target row has been deleted. Null where the change was
  about no one in particular, such as editing a leave type.
  """

  use Leaf.Schema

  alias Leaf.People.Person

  @type t :: %__MODULE__{}

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  @fields [:actor_id, :subject_person_id, :action, :entity_type, :entity_id, :changes]

  schema "audit_log_entries" do
    field :action, :string
    field :entity_type, :string
    field :entity_id, Ecto.UUID
    field :changes, :map

    belongs_to :actor, Person
    belongs_to :subject_person, Person

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @fields)
    |> validate_required([:action, :entity_type, :entity_id, :changes])
    |> assoc_constraint(:actor)
    |> assoc_constraint(:subject_person)
  end
end
