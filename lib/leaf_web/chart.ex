defmodule LeafWeb.Chart do
  @moduledoc "Where dated figures fall on a balance chart drawn in a 600 by 200 box."

  @doc """
  A function placing a dated figure on a chart running from `from` to `to`.

  The chart runs from the lower of zero and the least of `figures` up to the greatest, so a balance
  that goes negative still shows where zero is.
  """
  @spec placing(Date.t(), Date.t(), [Decimal.t()]) ::
          ({Date.t(), Decimal.t()} -> {integer(), integer()})
  def placing(from, to, figures) do
    values = Enum.map(figures, &Decimal.to_float/1)
    bottom = Enum.min([0 | values])
    height = Enum.max([bottom + 1 | values]) - bottom
    days = Date.diff(to, from)

    fn {date, figure} ->
      {round(Date.diff(date, from) * 600 / days),
       round(195 - (Decimal.to_float(figure) - bottom) * 190 / height)}
    end
  end

  @doc "Dated figures as the points of a polyline, placed by `place`."
  @spec points([{Date.t(), Decimal.t()}], ({Date.t(), Decimal.t()} -> {integer(), integer()})) ::
          String.t()
  def points(figures, place) do
    Enum.map_join(figures, " ", fn figure ->
      {x, y} = place.(figure)
      "#{x},#{y}"
    end)
  end
end
