defmodule Leaf.Ledger.Drawdown do
  @moduledoc """
  Walks a leave type's movements in date order, holding what arrives and spending what does not.

  Anything that adds to a balance becomes a lot with the date it lapses on. Anything that takes
  from one — leave filed, or an adjustment correcting a balance downwards — comes off the soonest
  to lapse of the lots still live on its date, so nothing lapses that could have been used and
  nothing is paid for out of what had already gone.

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

  `caps` gives the dates a cap falls due with the cap that applies. Up to `as_at` the whole ledger
  happens; past it the only movements left are leave already approved for later, which draws on
  what is held. Nothing arrives after `as_at`, nothing lapses and no cap falls, so a lot due to
  lapse later is still held.
  """
  @spec run([Movement.t()], [{Date.t(), Decimal.t()}], Date.t()) ::
          {[Movement.t()], [Lot.t()]}
  def run(movements, caps, as_at) do
    by_date = Enum.group_by(movements, & &1.date)
    {elapsed, ahead} = dates(movements, caps, as_at)
    start = %{lots: [], deficit: Decimal.new(0), movements: []}

    held =
      Enum.reduce(elapsed, start, fn date, state ->
        state
        |> apply_movements(Map.get(by_date, date, []))
        |> expire(date)
        |> trim(date, caps)
      end)

    state = Enum.reduce(ahead, held, &apply_movements(&2, Map.get(by_date, &1, [])))

    {Enum.reverse(state.movements), Lot.soonest_first(state.lots)}
  end

  # Every date something happens on, split at `as_at`. A lapse or a cap due after it has not
  # happened yet and so is left out altogether, rather than falling due at whatever later date the
  # walk happens to reach.
  defp dates(movements, caps, as_at) do
    losses = Enum.flat_map(movements, &lapse_date/1) ++ Enum.map(caps, &elem(&1, 0))

    (Enum.map(movements, & &1.date) ++ Enum.reject(losses, &Date.after?(&1, as_at)))
    |> Enum.uniq()
    |> Enum.sort(Date)
    |> Enum.split_while(&(not Date.after?(&1, as_at)))
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
      true -> draw(state, Decimal.abs(movement.amount), movement.date)
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

  # A lot that has lapsed by the date leave is taken on cannot pay for it, even where the walk is
  # still holding it because nothing lapses past `as_at`.
  defp draw(state, amount, date) do
    {live, lapsed} = Enum.split_with(state.lots, &live?(&1, date))
    {drawn, shortfall} = consume(Lot.soonest_first(live), amount)

    %{state | lots: drawn ++ lapsed, deficit: Decimal.add(state.deficit, shortfall)}
  end

  defp live?(%{expires_on: nil}, _date), do: true
  defp live?(lot, date), do: not Date.before?(lot.expires_on, date)

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
