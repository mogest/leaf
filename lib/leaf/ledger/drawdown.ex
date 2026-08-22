defmodule Leaf.Ledger.Drawdown do
  @moduledoc """
  Walks a leave type's movements in date order, holding what arrives and spending what does not.

  Anything that adds to a balance becomes a lot with the date it lapses on. Anything that takes
  from one — leave filed, or an adjustment correcting a balance downwards — comes off the lot that
  lapses soonest, so nothing lapses that could have been used.

  Every loss shows as a movement of its own, because a balance should never quietly disappear: a
  lot unspent on the day it lapses expires, and where a leave type rolls over only up to a cap,
  the excess at the end of a grant period is trimmed from the lots with the longest left to run —
  the ones that would otherwise survive it.

  Taking more than is held is allowed. The shortfall is carried and paid off by whatever arrives
  next, which is what accruing back from a negative balance amounts to.
  """

  alias Leaf.Ledger.Lot
  alias Leaf.Ledger.Movement

  @doc """
  The movements in the order they happened, and the lots still held on `as_at`.

  `caps` gives the dates a cap falls due with the cap that applies. Anything dated after `as_at`
  takes no part in the walk, so a lot due to lapse later is still held.
  """
  @spec run([Movement.t()], [{Date.t(), Decimal.t()}], Date.t()) ::
          {[Movement.t()], [Lot.t()]}
  def run(movements, caps, as_at) do
    by_date = Enum.group_by(movements, & &1.date)
    start = %{lots: [], deficit: Decimal.new(0), movements: []}

    state =
      Enum.reduce(dates(movements, caps, as_at), start, fn date, state ->
        state
        |> apply_movements(Map.get(by_date, date, []))
        |> expire(date)
        |> trim(date, caps)
      end)

    {Enum.reverse(state.movements), Lot.soonest_first(state.lots)}
  end

  defp dates(movements, caps, as_at) do
    (Enum.flat_map(movements, &[&1.date | lapse_date(&1)]) ++ Enum.map(caps, &elem(&1, 0)))
    |> Enum.reject(&Date.after?(&1, as_at))
    |> Enum.uniq()
    |> Enum.sort(Date)
  end

  defp lapse_date(%{expires_on: nil}), do: []
  defp lapse_date(movement), do: [movement.expires_on]

  defp apply_movements(state, movements) do
    Enum.reduce(movements, state, fn movement, state ->
      state |> record(movement) |> move(movement)
    end)
  end

  defp move(state, movement) do
    case Decimal.negative?(movement.amount) do
      true -> draw(state, Decimal.abs(movement.amount))
      false -> hold(state, movement.amount, movement.expires_on)
    end
  end

  defp hold(state, amount, expires_on) do
    {held, deficit} = settle(amount, state.deficit)

    %{state | deficit: deficit, lots: add(state.lots, held, expires_on)}
  end

  defp settle(amount, deficit) do
    paid = Enum.min([amount, deficit], Decimal)

    {Decimal.sub(amount, paid), Decimal.sub(deficit, paid)}
  end

  defp add(lots, amount, expires_on) do
    case Decimal.positive?(amount) do
      true -> [%Lot{amount: amount, expires_on: expires_on} | lots]
      false -> lots
    end
  end

  defp draw(state, amount) do
    {lots, shortfall} = consume(Lot.soonest_first(state.lots), amount)

    %{state | lots: lots, deficit: Decimal.add(state.deficit, shortfall)}
  end

  defp expire(state, date) do
    {lapsed, held} = Enum.split_with(state.lots, &lapsed?(&1, date))

    Enum.reduce(lapsed, %{state | lots: held}, fn lot, state ->
      record(state, %Movement{date: date, kind: :expiry, amount: Decimal.negate(lot.amount)})
    end)
  end

  defp lapsed?(%{expires_on: nil}, _date), do: false
  defp lapsed?(lot, date), do: not Date.after?(lot.expires_on, date)

  defp trim(state, date, caps) do
    case List.keyfind(caps, date, 0) do
      nil -> state
      {_date, cap} -> trim_to(state, date, cap)
    end
  end

  defp trim_to(state, date, cap) do
    excess = Decimal.sub(Lot.total(state.lots), cap)

    case Decimal.positive?(excess) do
      false ->
        state

      true ->
        {lots, _shortfall} = consume(Lot.latest_first(state.lots), excess)

        state
        |> record(%Movement{date: date, kind: :rollover_cap, amount: Decimal.negate(excess)})
        |> Map.put(:lots, lots)
    end
  end

  defp consume([], amount), do: {[], amount}

  defp consume([lot | rest], amount) do
    case Decimal.compare(lot.amount, amount) do
      :gt -> {[%{lot | amount: Decimal.sub(lot.amount, amount)} | rest], Decimal.new(0)}
      _ -> consume(rest, Decimal.sub(amount, lot.amount))
    end
  end

  defp record(state, movement), do: %{state | movements: [movement | state.movements]}
end
