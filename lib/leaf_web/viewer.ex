defmodule LeafWeb.Viewer do
  @moduledoc """
  What the chrome knows about whoever is signed in.

  Whether somebody administers the organisation, or has anybody to approve for, decides what the
  rail offers them. Both are asked once a mount rather than at render, and they sit here rather
  than on the person because neither is a fact about their record.
  """

  alias Leaf.People
  alias Leaf.People.Person

  @type t :: %__MODULE__{person: Person.t(), admin?: boolean(), approver?: boolean()}

  @enforce_keys [:person, :admin?, :approver?]
  defstruct [:person, :admin?, :approver?]

  @doc "Builds the viewer for `person`, asking what their standing lets them reach."
  @spec new(Person.t()) :: t()
  def new(person) do
    admin? = person.role == :admin

    %__MODULE__{person: person, admin?: admin?, approver?: admin? or People.manager?(person)}
  end
end
