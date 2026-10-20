defmodule Leaf.Reports.OverLimit do
  @moduledoc """
  Everyone holding more of a leave type than a limit in weeks, a row for each balance over it.

  A week is the person's own, as their work pattern on the date has it: its hours where the type
  counts in hours, its working days where it counts in days. So a part-timer's limit is smaller.
  """

  alias Leaf.Ledger
  alias Leaf.People
  alias Leaf.Reports.Table

  @columns [
    "Person",
    "Leave type",
    "Balance without booked leave",
    "Booked leave",
    "Balance with booked leave",
    "Limit",
    "Excess",
    "Unit"
  ]

  @doc "The balances of `leave_type_id`, or of every type where nil, over `weeks` on `as_at`."
  @spec table(Ecto.UUID.t(), Date.t(), Ecto.UUID.t() | nil, Decimal.t()) :: Table.t()
  def table(organisation_id, as_at, leave_type_id, weeks) do
    {ready, unready} =
      organisation_id
      |> People.employed(Date.range(as_at, as_at))
      |> Enum.split_with(&Ledger.ready?(&1, as_at))

    held =
      for person <- ready,
          statements =
            Enum.filter(
              Ledger.balances(person, as_at),
              &(leave_type_id in [nil, &1.leave_type.id])
            ),
          statements != [],
          do: {person, People.fetch_work_pattern_on(person, as_at), statements}

    rows =
      for {person, {:ok, pattern}, statements} <- held,
          %{leave_type: leave_type, balance: balance, to_date: to_date} <- statements,
          limit = Decimal.mult(weeks, week(leave_type.unit, pattern)),
          Decimal.gt?(balance, limit) do
        [
          person.name,
          leave_type.name,
          to_date,
          Decimal.sub(to_date, balance),
          balance,
          limit,
          Decimal.sub(balance, limit),
          to_string(leave_type.unit)
        ]
      end

    patternless = for {person, :error, _statements} <- held, do: person

    %Table{columns: @columns, rows: rows, notes: Table.unmeasured(unready ++ patternless)}
  end

  defp week(:hours, pattern), do: People.weekly_hours(pattern)
  defp week(:days, pattern), do: People.weekly_days(pattern)
end
