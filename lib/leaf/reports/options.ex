defmodule Leaf.Reports.Options do
  @moduledoc """
  What a report is asked for: which report, and over which dates.

  Every report reads its own fields and ignores the rest, so they share one set, each with a
  default that answers the obvious question: this month, against the last payroll run before it,
  as at today.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Leaf.Changeset

  @type t :: %__MODULE__{}

  @reports [:ipayroll, :taken, :reconciliation, :balances, :expiring]

  @required [:report, :from, :to, :cut_off, :as_at, :within]
  @fields @required ++ [:country_id, :leave_type_id]

  @primary_key false
  embedded_schema do
    field :report, Ecto.Enum, values: @reports
    field :from, :date
    field :to, :date
    field :cut_off, :date
    field :as_at, :date
    field :within, :integer
    field :country_id, :binary_id
    field :leave_type_id, :binary_id
  end

  @doc "The options `params` ask for, defaulting from `today`."
  @spec changeset(Date.t(), map()) :: Ecto.Changeset.t()
  def changeset(today, params) do
    from = Date.beginning_of_month(today)

    %__MODULE__{
      report: :ipayroll,
      from: from,
      to: Date.end_of_month(today),
      cut_off: Date.add(from, -1),
      as_at: today,
      within: 60
    }
    |> cast(params, @fields)
    |> validate_required(@required)
    |> validate_date_order(:from, :to)
    |> validate_number(:within, greater_than: 0, less_than_or_equal_to: 3660)
  end

  @doc "The dates from `from` to `to`."
  @spec period(t()) :: Date.Range.t()
  def period(options), do: Date.range(options.from, options.to)
end
