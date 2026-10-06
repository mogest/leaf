defmodule Leaf.Messaging.Channel do
  @moduledoc """
  A way of reaching people: Slack now, email later.

  An address the channel finds nobody at is `{:error, :not_found}`, which is somebody's details
  being out of step rather than the channel failing.
  """

  alias Leaf.Messaging.Message
  alias Leaf.People.Person

  @doc "The name a message sent through the channel is recorded under, which must never change."
  @callback name() :: String.t()

  @doc "Where the channel reaches the person, or nil where it cannot."
  @callback address(Person.t()) :: String.t() | nil

  @doc "Sends a message, returning what the channel needs to find it again."
  @callback send(address :: String.t(), Message.t()) ::
              {:ok, receipt :: map()} | {:error, :not_found | term()}

  @doc "Rewrites a message already sent."
  @callback replace(receipt :: map(), Message.t()) :: :ok | {:error, term()}
end
