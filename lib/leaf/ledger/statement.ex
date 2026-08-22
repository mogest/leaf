defmodule Leaf.Ledger.Statement do
  @moduledoc """
  One leave type's account: how the balance was arrived at, what is still held, and the balance.

  `movements` and `lots` carry exact figures. `balance` is the sum of the movements rounded to two
  places, being the figure that gets shown, so an account always adds up to what it says it does.

  `as_at` is the date it accrued to, which a projection moves on to the end of the leave it is
  asked about, so the figure can say which date it speaks for rather than leaving that to whoever
  shows it.
  """

  alias Leaf.Ledger.Lot
  alias Leaf.Ledger.Movement
  alias Leaf.Policies.LeaveType

  @type t :: %__MODULE__{
          leave_type: LeaveType.t(),
          as_at: Date.t(),
          movements: [Movement.t()],
          lots: [Lot.t()],
          balance: Decimal.t()
        }

  @enforce_keys [:leave_type, :as_at, :movements, :lots, :balance]
  defstruct [:leave_type, :as_at, :movements, :lots, :balance]

  @doc "The account the movements add up to."
  @spec new(LeaveType.t(), Date.t(), [Movement.t()], [Lot.t()]) :: t()
  def new(leave_type, as_at, movements, lots) do
    %__MODULE__{
      leave_type: leave_type,
      as_at: as_at,
      movements: movements,
      lots: lots,
      balance: movements |> Movement.total() |> Decimal.round(2)
    }
  end
end
