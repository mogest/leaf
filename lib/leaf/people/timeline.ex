defmodule Leaf.People.Timeline do
  @moduledoc """
  Slices an effective-dated succession into the span each row governs.

  Work patterns, policy assignments and calendar assignments all work the same way: a row applies
  from its `effective_from` until the next row supersedes it, and carries no end date of its own.
  """

  @typedoc "Any effective-dated row in a succession."
  @type row :: %{:effective_from => Date.t(), optional(atom()) => term()}

  @doc """
  The row in force on `date`.

  `:error` before the first row takes effect.
  """
  @spec fetch([row()], Date.t()) :: {:ok, row()} | :error
  def fetch(rows, date) do
    rows
    |> in_order()
    |> Enum.take_while(&(not Date.after?(&1.effective_from, date)))
    |> List.last()
    |> found()
  end

  @doc """
  Each row governing part of `range`, with the span of `range` it governs, in order.

  Spans are clipped to `range`. The stretch before the first row takes effect belongs to no row
  and so appears in nothing.
  """
  @spec segments([row()], Date.Range.t()) :: [{Date.Range.t(), row()}]
  def segments(rows, range) do
    ordered = in_order(rows)

    ordered
    |> Enum.zip(Enum.drop(ordered, 1) ++ [nil])
    |> Enum.flat_map(fn {row, successor} -> clip(row, successor, range) end)
  end

  defp in_order(rows), do: Enum.sort_by(rows, & &1.effective_from, Date)

  defp found(nil), do: :error
  defp found(row), do: {:ok, row}

  defp clip(row, successor, range) do
    from = latest(row.effective_from, range.first)
    to = earliest(superseded_on(successor), range.last)

    case Date.compare(from, to) do
      :gt -> []
      _ -> [{Date.range(from, to), row}]
    end
  end

  defp superseded_on(nil), do: nil
  defp superseded_on(successor), do: Date.add(successor.effective_from, -1)

  defp earliest(nil, date), do: date
  defp earliest(a, b), do: Enum.min([a, b], Date)

  defp latest(a, b), do: Enum.max([a, b], Date)
end
