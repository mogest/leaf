defmodule Leaf.Reports.Balances do
  @moduledoc """
  What everyone employed holds as at a date: a row a person, a column a leave type in its own unit.

  A type recorded only has no balance, so it has no column; somebody holding nothing has no row,
  and nor does somebody whose balance cannot be worked out, which a note says.
  """

  alias Leaf.Ledger
  alias Leaf.People
  alias Leaf.Policies
  alias Leaf.Reports.Table

  @doc "The balances everyone employed on `as_at` holds on it."
  @spec table(Ecto.UUID.t(), Date.t()) :: Table.t()
  def table(organisation_id, as_at) do
    {ready, unready} =
      organisation_id
      |> People.employed(Date.range(as_at, as_at))
      |> Enum.split_with(&Ledger.ready?(&1, as_at))

    held =
      ready
      |> Enum.map(
        &{&1, Map.new(Ledger.balances(&1, as_at), fn s -> {s.leave_type.id, s.balance} end)}
      )
      |> Enum.reject(fn {_person, balances} -> balances == %{} end)

    ids = held |> Enum.flat_map(fn {_person, balances} -> Map.keys(balances) end) |> MapSet.new()
    leave_types = organisation_id |> Policies.leave_types() |> Enum.filter(&(&1.id in ids))

    %Table{
      columns: ["Person" | Enum.map(leave_types, &"#{&1.name} (#{&1.unit})")],
      rows:
        Enum.map(held, fn {person, balances} ->
          [person.name | Enum.map(leave_types, &balances[&1.id])]
        end),
      notes: Table.unmeasured(unready)
    }
  end
end
