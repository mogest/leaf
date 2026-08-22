defmodule Leaf.Ledger.Statement do
  @moduledoc """
  One leave type's account: how the balance was arrived at, what is still held, and the balance.

  `movements` and `lots` carry exact figures. `balance` is the sum of the movements rounded to two
  places, being the figure that gets shown, so an account always adds up to what it says it does.
  """

  alias Leaf.Ledger.Lot
  alias Leaf.Ledger.Movement
  alias Leaf.Policies.LeaveType

  @type t :: %__MODULE__{
          leave_type: LeaveType.t(),
          movements: [Movement.t()],
          lots: [Lot.t()],
          balance: Decimal.t()
        }

  @enforce_keys [:leave_type, :movements, :lots, :balance]
  defstruct [:leave_type, :movements, :lots, :balance]

  @doc "The account the movements add up to."
  @spec new(LeaveType.t(), [Movement.t()], [Lot.t()]) :: t()
  def new(leave_type, movements, lots) do
    %__MODULE__{
      leave_type: leave_type,
      movements: movements,
      lots: lots,
      balance: movements |> Movement.total() |> Decimal.round(2)
    }
  end
end
