defmodule Leaf.People.Person do
  @moduledoc """
  Someone whose leave the system tracks, and their login account.

  Employee or contractor is not a distinction made here — it is expressed by which leave policy
  the person is on. Manager is not a role either: it follows from having reports.
  """

  use Leaf.Schema

  alias Leaf.Org.Organisation

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
    :birth_date
  ]

  schema "people" do
    field :name, :string
    field :email, :string
    field :google_sub, :string
    field :role, Ecto.Enum, values: @roles
    field :employment_start_date, :date
    field :employment_end_date, :date
    field :birth_date, :date

    belongs_to :organisation, Organisation
    belongs_to :manager, __MODULE__

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(person, attrs) do
    person
    |> cast(attrs, @fields)
    |> validate_required([:organisation_id, :name, :email, :role, :employment_start_date])
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+$/)
    |> validate_date_order(:employment_start_date, :employment_end_date)
    |> validate_manager_is_someone_else()
    |> unique_constraint(:email)
    |> unique_constraint(:google_sub)
    |> assoc_constraint(:organisation)
    |> assoc_constraint(:manager)
  end

  # A longer loop — A reports to B reports to A — needs a walk of the reporting lines, so it
  # belongs wherever those are edited rather than here.
  defp validate_manager_is_someone_else(changeset) do
    case {changeset.data.id, get_field(changeset, :manager_id)} do
      {nil, _manager_id} -> changeset
      {id, id} -> add_error(changeset, :manager_id, "cannot be the person themselves")
      _ -> changeset
    end
  end
end
