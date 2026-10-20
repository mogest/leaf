defmodule Leaf.Ledger.Movement do
  @moduledoc """
  One thing that happened to a balance, and the amount it moved it by.

  Amounts are signed, so a balance is the sum of the movements that made it — which is what makes
  a balance explainable rather than merely correct.

  A grant or an accrual arrives with the date it lapses on, if it lapses. Everything a person
  loses is a movement of its own: leave taken, a lot that lapsed unused, and the excess trimmed
  where a leave type rolls over only up to a cap.

  A figure entered by hand with a lapse date of its own is not `capped`: a cap neither counts nor
  trims it. That is how leave the law carries over past the cap is held — UK leave a person could
  not take for sickness or family leave, which lapses on a deadline of its own.

  An accrual says how much of it was earned in each month its dates run through, in `months`, and
  leave taken says which request it was taken in. Neither changes what the movement does to a
  balance; they are what lets its history be read a month and a request at a time.
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
          expires_on: Date.t() | nil,
          capped: boolean(),
          months: [{Date.Range.t(), Decimal.t()}] | nil,
          leave_request_id: Ecto.UUID.t() | nil
        }

  @enforce_keys [:date, :kind, :amount]
  defstruct [:date, :kind, :amount, :expires_on, :months, :leave_request_id, capped: true]
end
