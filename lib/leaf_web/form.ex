defmodule LeafWeb.Form do
  @moduledoc """
  Putting a changeset back on the page as a form that shows what it refused.
  """

  import Phoenix.Component

  alias Phoenix.LiveView.Socket

  @doc """
  Assigns a changeset as a form, with the action that makes its errors show.

  `key` names the form where a page holds more than one.
  """
  @spec validated(Socket.t(), Ecto.Changeset.t(), atom()) :: Socket.t()
  def validated(socket, changeset, key \\ :form) do
    assign(socket, key, to_form(changeset, action: :validate))
  end
end
