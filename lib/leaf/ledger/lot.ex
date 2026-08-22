defmodule Leaf.Ledger.Lot do
  @moduledoc """
  An amount of leave held, and the date it lapses on.

  A balance is a list of these rather than one figure, because which lot a day off came out of
  decides what is left: 40 hours that never lapse plus a 10 hour top-up that must be used by June
  is 42 hours either way once 8 hours are taken, but the June top-up either survives or does not.
  Leave always draws on the lot that lapses soonest, so nothing lapses that could have been used.

  `expires_on` is inclusive, and nil where the lot does not lapse at all.
  """

  @type t :: %__MODULE__{amount: Decimal.t(), expires_on: Date.t() | nil}

  @enforce_keys [:amount, :expires_on]
  defstruct [:amount, :expires_on]

  @doc "The lots in the order leave draws on them: soonest to lapse first, never-lapsing last."
  @spec soonest_first([t()]) :: [t()]
  def soonest_first(lots), do: Enum.sort_by(lots, & &1.expires_on, &lapses_no_later?/2)

  @doc "The reverse: the lots with the longest left to run first."
  @spec latest_first([t()]) :: [t()]
  def latest_first(lots), do: lots |> soonest_first() |> Enum.reverse()

  @doc "The total held across `lots`."
  @spec total([t()]) :: Decimal.t()
  def total(lots), do: Enum.reduce(lots, Decimal.new(0), &Decimal.add(&2, &1.amount))

  defp lapses_no_later?(nil, nil), do: true
  defp lapses_no_later?(nil, _later), do: false
  defp lapses_no_later?(_earlier, nil), do: true
  defp lapses_no_later?(earlier, later), do: not Date.after?(earlier, later)
end
