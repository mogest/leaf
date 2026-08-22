defmodule Leaf.Dates do
  @moduledoc "Date helpers shared across areas."

  @doc "The narrowest range covering every one of `dates`."
  @spec spanning([Date.t()]) :: Date.Range.t()
  def spanning(dates), do: Date.range(Enum.min(dates, Date), Enum.max(dates, Date))
end
