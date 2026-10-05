defmodule Leaf.Dates do
  @moduledoc "Date helpers shared across areas."

  @doc "The narrowest range covering every one of `dates`."
  @spec spanning([Date.t()]) :: Date.Range.t()
  def spanning(dates), do: Date.range(Enum.min(dates, Date), Enum.max(dates, Date))

  @doc """
  The earlier of two dates, where `nil` is no bound at all and so the other date wins.

  Two `nil`s are `nil`.
  """
  @spec earliest(Date.t() | nil, Date.t() | nil) :: Date.t() | nil
  def earliest(nil, date), do: date
  def earliest(date, nil), do: date
  def earliest(a, b), do: Enum.min([a, b], Date)

  @doc """
  The part of `range` from `from` to `to`, where a `to` of `nil` is no bound at all.

  `:error` where they leave nothing.
  """
  @spec intersect(Date.Range.t(), Date.t(), Date.t() | nil) :: {:ok, Date.Range.t()} | :error
  def intersect(range, from, to) do
    bounded(Enum.max([range.first, from], Date), earliest(range.last, to))
  end

  @doc "The range from `first` to `last`, or `:error` where `last` is before `first`."
  @spec bounded(Date.t(), Date.t()) :: {:ok, Date.Range.t()} | :error
  def bounded(first, last) do
    case Date.compare(first, last) do
      :gt -> :error
      _ -> {:ok, Date.range(first, last)}
    end
  end
end
