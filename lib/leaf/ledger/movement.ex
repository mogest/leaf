defmodule Leaf.Ledger.Movement do
  @moduledoc """
  One thing that happened to a balance, and the amount it moved it by.

  Amounts are signed, so a balance is the sum of the movements that made it — which is what makes
  a balance explainable rather than merely correct.

  A grant or an accrual arrives with the date it lapses on, if it lapses. Everything a person
  loses is a movement of its own: leave taken, a lot that lapsed unused, and the excess trimmed
  where a leave type rolls over only up to a cap.
  """

  @typedoc "What moved the balance. The first four add to it; the last three take from it."
  @type kind ::
          :opening_balance
          | :adjustment
          | :grant
          | :accrual
          | :taken
          | :expiry
          | :rollover_cap

  @type t :: %__MODULE__{
          date: Date.t(),
          kind: kind(),
          amount: Decimal.t(),
          expires_on: Date.t() | nil
        }

  @enforce_keys [:date, :kind, :amount]
  defstruct [:date, :kind, :amount, :expires_on]

  @doc "The total the movements come to."
  @spec total([t()]) :: Decimal.t()
  def total(movements), do: Enum.reduce(movements, Decimal.new(0), &Decimal.add(&2, &1.amount))
end
