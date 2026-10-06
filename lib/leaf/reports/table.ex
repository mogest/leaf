defmodule Leaf.Reports.Table do
  @moduledoc """
  A report: its rows under its column headings, and what a reader should know it leaves out.

  Cells hold the values themselves rather than text, so a page and a file can each say them their
  own way. Figures are exact, rounded only where they are said.
  """

  alias Leaf.People.Person

  @type cell :: String.t() | Date.t() | DateTime.t() | Decimal.t() | nil
  @type t :: %__MODULE__{columns: [String.t()], rows: [[cell()]], notes: [String.t()]}

  @enforce_keys [:columns, :rows]
  defstruct [:columns, :rows, notes: []]

  @doc """
  The table as CSV: the headings, then a line a row, dates day first and figures to 2dp.

  A moment is said as it was in `zone`.
  """
  @spec csv(t(), String.t()) :: String.t()
  def csv(table, zone) do
    Enum.map_join(
      [table.columns | table.rows],
      &[Enum.map_join(&1, ",", fn cell -> field(cell, zone) end), "\r\n"]
    )
  end

  @doc "What to say of `people` whose leave is left out for having no work pattern under it."
  @spec unmeasured([Person.t()]) :: [String.t()]
  def unmeasured(people) do
    for person <- Enum.uniq_by(people, & &1.id) do
      "#{person.name}'s work pattern does not cover their leave, so it is left out."
    end
  end

  defp field(cell, zone), do: cell |> text(zone) |> quoted()

  defp text(nil, _zone), do: ""
  defp text(%Date{} = date, _zone), do: Calendar.strftime(date, "%d/%m/%Y")

  defp text(%DateTime{} = at, zone),
    do: at |> DateTime.shift_zone!(zone) |> Calendar.strftime("%d/%m/%Y %H:%M")

  defp text(%Decimal{} = amount, _zone),
    do: amount |> Decimal.round(2) |> Decimal.to_string(:normal)

  defp text(string, _zone), do: string

  defp quoted(text) do
    case String.contains?(text, [",", "\"", "\r", "\n"]) do
      true -> ~s("#{String.replace(text, "\"", "\"\"")}")
      false -> text
    end
  end
end
