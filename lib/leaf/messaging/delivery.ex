defmodule Leaf.Messaging.Delivery do
  @moduledoc """
  A message sent to somebody, kept so that it can be rewritten.

  `receipt` is whatever the channel needs to find the message again.
  """

  use Leaf.Schema

  alias Leaf.People.Person

  @type t :: %__MODULE__{}

  schema "message_deliveries" do
    field :channel, :string
    field :topic, :string
    field :receipt, :map

    belongs_to :person, Person

    timestamps()
  end
end
