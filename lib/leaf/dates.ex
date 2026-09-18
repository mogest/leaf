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
end
