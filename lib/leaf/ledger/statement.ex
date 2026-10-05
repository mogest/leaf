defmodule Leaf.Ledger.Statement do
  @moduledoc """
  One leave type's account: how the balance was arrived at, what is still held, and the balance.

  `movements` and `lots` carry exact figures. `balance` is the sum of the movements rounded to two
  places, being the figure that gets shown, so an account always adds up to what it says it does.

  `lots` are in the order leave draws on them — soonest to lapse first, never-lapsing last — so
  whoever reads the one about to lapse reads the first, rather than sorting them again.

  `as_at` is the date it accrued to, which a projection moves on to the end of the leave it is
  asked about, so the figure can say which date it speaks for rather than leaving that to whoever
  shows it.

  `recorded_only` is a type the person is granted nothing in, by their policy or by hand, so the
  balance is only the leave taken against it and there is nothing for it to go under.
  """

  alias Leaf.Ledger.Lot
  alias Leaf.Ledger.Movement
  alias Leaf.Policies.LeaveType

  @type t :: %__MODULE__{
          leave_type: LeaveType.t(),
          as_at: Date.t(),
          movements: [Movement.t()],
          lots: [Lot.t()],
          balance: Decimal.t(),
          recorded_only: boolean()
        }

  @enforce_keys [:leave_type, :as_at, :movements, :lots, :balance, :recorded_only]
  defstruct [:leave_type, :as_at, :movements, :lots, :balance, :recorded_only]

  @doc "The account the movements add up to."
  @spec new(LeaveType.t(), Date.t(), [Movement.t()], [Lot.t()], boolean()) :: t()
  def new(leave_type, as_at, movements, lots, recorded_only) do
    %__MODULE__{
      leave_type: leave_type,
      as_at: as_at,
      movements: movements,
      lots: Lot.soonest_first(lots),
      balance: movements |> Movement.total() |> Decimal.round(2),
      recorded_only: recorded_only
    }
  end
end
