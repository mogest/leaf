defmodule Leaf.Leave.Request do
  @moduledoc """
  A request for leave.

  It carries no dates of its own: the `days` are the record of what was taken.

  Who a request belongs to is settled when it is made and never cast again, so an amendment cannot
  move it to somebody else. `changeset/2` covers requesting and amending, and always owns the days.
  Deciding one is a distinct state, so `review_changeset/2` handles it separately and cannot touch
  the days. Which decisions may follow which is `Leaf.Leave`'s to say — it turns on who is acting,
  which a changeset cannot see.
  """

  use Leaf.Schema

  alias Leaf.Leave.Day
  alias Leaf.People.Person

  @type t :: %__MODULE__{}

  @statuses [:pending, :approved, :declined, :cancelled]
  @decided [:approved, :declined, :cancelled]

  @review_fields [:status, :reviewed_by_id, :reviewed_at, :review_comment]

  schema "leave_requests" do
    field :status, Ecto.Enum, values: @statuses
    field :note, :string
    field :reviewed_at, :utc_datetime
    field :review_comment, :string

    belongs_to :person, Person
    belongs_to :submitted_by, Person
    belongs_to :reviewed_by, Person
    has_many :days, Day, foreign_key: :leave_request_id, on_replace: :delete

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(request, attrs) do
    request
    |> cast(attrs, [:note])
    |> validate_required([:person_id, :submitted_by_id, :status])
    |> cast_assoc(:days, required: true)
    |> assoc_constraint(:person)
    |> assoc_constraint(:submitted_by)
  end

  @doc """
  Records a decision.

  A cancellation is a decision too, so `reviewed_by` on a cancelled request is whoever cancelled
  it rather than whoever approved it. The approval it replaced is in the audit log.
  """
  @spec review_changeset(t(), map()) :: Ecto.Changeset.t()
  def review_changeset(request, attrs) do
    request
    |> cast(attrs, @review_fields)
    |> validate_required([:status, :reviewed_by_id, :reviewed_at])
    |> validate_inclusion(:status, @decided)
    |> assoc_constraint(:reviewed_by)
  end
end
