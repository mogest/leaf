defmodule Leaf.Reports.Options do
  @moduledoc """
  What a report is asked for: which report, and over which dates.

  Every report reads its own fields and ignores the rest, so they share one set, each with a
  default that answers the obvious question: this month.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Leaf.Changeset

  @type t :: %__MODULE__{}

  @reports [:ipayroll]

  @fields [:report, :from, :to]

  @primary_key false
  embedded_schema do
    field :report, Ecto.Enum, values: @reports
    field :from, :date
    field :to, :date
  end

  @doc "The options `params` ask for, defaulting from `today`."
  @spec changeset(Date.t(), map()) :: Ecto.Changeset.t()
  def changeset(today, params) do
    %__MODULE__{
      report: :ipayroll,
      from: Date.beginning_of_month(today),
      to: Date.end_of_month(today)
    }
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> validate_date_order(:from, :to)
  end

  @doc "The dates from `from` to `to`."
  @spec period(t()) :: Date.Range.t()
  def period(options), do: Date.range(options.from, options.to)
end
