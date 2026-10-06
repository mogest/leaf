defmodule Leaf.Decimals do
  @moduledoc "Decimal helpers shared across areas."

  @doc "The sum of `fun` over `enumerable`, an empty one coming to zero."
  @spec total(Enumerable.t(), (term() -> Decimal.t())) :: Decimal.t()
  def total(enumerable, fun \\ & &1) do
    Enum.reduce(enumerable, Decimal.new(0), &Decimal.add(&2, fun.(&1)))
  end
end
