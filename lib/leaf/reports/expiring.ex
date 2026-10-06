defmodule Leaf.Reports.Expiring do
  @moduledoc """
  Leave due to lapse soon, a row for each date somebody's holding of a leave type lapses on.

  Read off what each lot holds as at the date asked about, after every approved day has drawn on
  the lot lapsing soonest, so it is what will go unless more leave is taken before then.
  """

  alias Leaf.Decimals
  alias Leaf.Ledger
  alias Leaf.People
  alias Leaf.Reports.Table

  @columns ["Person", "Leave type", "Amount", "Unit", "Lapses on"]

  @doc "What everyone employed on `as_at` holds that lapses within `within` days of it."
  @spec table(Ecto.UUID.t(), Date.t(), pos_integer()) :: Table.t()
  def table(organisation_id, as_at, within) do
    soon = Date.range(as_at, Date.add(as_at, within))

    {ready, unready} =
      organisation_id
      |> People.employed(Date.range(as_at, as_at))
      |> Enum.split_with(&Ledger.ready?(&1, as_at))

    rows =
      for person <- ready,
          statement <- Ledger.balances(person, as_at),
          {lapses_on, lots} <- Enum.group_by(statement.lots, & &1.expires_on),
          lapses_on && lapses_on in soon,
          amount = Decimals.total(lots, & &1.amount) do
        [
          person.name,
          statement.leave_type.name,
          amount,
          to_string(statement.leave_type.unit),
          lapses_on
        ]
      end

    %Table{
      columns: @columns,
      rows: Enum.sort_by(rows, &List.last/1, Date),
      notes: Table.unmeasured(unready)
    }
  end
end
