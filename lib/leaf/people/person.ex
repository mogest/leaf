defmodule Leaf.People.Person do
  @moduledoc """
  Someone whose leave the system tracks, and their login account.

  Employee or contractor is not a distinction made here — it is expressed by which leave policy
  the person is on. Manager is not a role either: it follows from having reports.

  `employee_number` is who they are to the payroll system, which is how its export names them.
  """

  use Leaf.Schema

  alias Leaf.Org.Organisation
  alias Leaf.People.PersonCalendar
  alias Leaf.People.PersonPolicyAssignment
  alias Leaf.People.WorkPattern

  @type t :: %__MODULE__{}

  @roles [:member, :admin]

  # `google_sub` is deliberately absent: it is the authentication identity, so it is set on the
  # struct where an account is bound and never cast, or a crafted form param binds somebody else's.
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
    field :google_sub, :string
    field :role, Ecto.Enum, values: @roles
    field :employment_start_date, :date
    field :employment_end_date, :date
    field :birth_date, :date
    field :employee_number, :string

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
    |> unique_constraint(:google_sub)
    |> unique_constraint(:employee_number, name: :people_organisation_id_employee_number_index)
    |> assoc_constraint(:organisation)
    |> assoc_constraint(:manager)
  end
end
