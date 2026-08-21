defmodule Leaf.People.PersonToken do
  @moduledoc "A session token belonging to a person."

  use Leaf.Schema

  alias Leaf.People.Person

  @type t :: %__MODULE__{}

  @timestamps_opts [type: :utc_datetime, updated_at: false]

  schema "person_tokens" do
    field :token, :binary
    field :context, :string

    belongs_to :person, Person

    timestamps()
  end
end
