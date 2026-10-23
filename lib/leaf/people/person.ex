defmodule Leaf.People.Person do
  @moduledoc """
  Someone whose leave the system tracks.

  Employee or contractor is not a distinction made here — it is expressed by which leave policy
  the person is on. Manager is not a role either: it follows from having reports.

  `email` is who they sign in as: whoever the identity provider vouches for at that address.

  `employee_number` is who they are to the payroll system, which is how its export names them.

  `archived_at` is set only by `Leaf.People.archive_person/2`, so it is never cast. Both `email` and
  `employee_number` are unique only among people not archived.
  """

  use Leaf.Schema

  alias Leaf.Org.Organisation
  alias Leaf.People.PersonCalendar
  alias Leaf.People.PersonPolicyAssignment
  alias Leaf.People.WorkPattern

  @type t :: %__MODULE__{}

  @roles [:member, :admin]

  @fields [
    :manager_id,
    :name,
    :email,
    :role,
    :employment_start_date,
    :employment_end_date,
    :birth_date,
    :employee_number
  ]

  schema "people" do
    field :name, :string
    field :email, :string
    field :role, Ecto.Enum, values: @roles
    field :employment_start_date, :date
    field :employment_end_date, :date
    field :birth_date, :date
    field :employee_number, :string
    field :archived_at, :utc_datetime

    belongs_to :organisation, Organisation
    belongs_to :manager, __MODULE__
    has_many :work_patterns, WorkPattern, preload_order: [:effective_from]
    has_many :policy_assignments, PersonPolicyAssignment, preload_order: [:effective_from]
    has_many :calendar_assignments, PersonCalendar, preload_order: [:effective_from]

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(person, attrs) do
    person
    |> cast(attrs, @fields)
    |> validate_required([:organisation_id, :name, :email, :role, :employment_start_date])
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+$/)
    |> update_change(:email, &String.downcase/1)
    |> validate_date_order(:employment_start_date, :employment_end_date)
    |> unique_constraint(:email, name: :people_lower_email_index)
    |> unique_constraint(:employee_number, name: :people_organisation_id_employee_number_index)
    |> assoc_constraint(:organisation)
    |> assoc_constraint(:manager)
  end
end
