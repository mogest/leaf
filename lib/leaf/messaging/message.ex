defmodule Leaf.Messaging.Message do
  @moduledoc """
  What a message says, in no channel's markup.

  `path` is a page in Leaf the message points at, and each channel links it as it links things.
  """

  @enforce_keys [:text]
  defstruct [:text, path: nil]

  @type t :: %__MODULE__{text: String.t(), path: String.t() | nil}

  @doc "The page the message points at, as an absolute URL, or nil where it points at none."
  @spec url(t()) :: String.t() | nil
  def url(%{path: nil}), do: nil
  def url(%{path: path}), do: LeafWeb.Endpoint.url() <> path
end
