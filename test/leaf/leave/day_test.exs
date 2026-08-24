defmodule Leaf.Leave.DayTest do
  use Leaf.DataCase, async: true

  alias Leaf.Leave.Day

  test "a day converts to the unit asked for, on the hours worked on its date" do
    whole_day = %Day{amount: Decimal.new("1"), unit: :days}
    an_hour = %Day{amount: Decimal.new("1"), unit: :hours}
    nine = Decimal.new("9")

    assert Decimal.equal?(Day.in_unit(whole_day, :hours, nine), "9")
    assert Decimal.equal?(Day.in_unit(whole_day, :days, nine), "1")
    assert Decimal.equal?(Day.in_unit(an_hour, :hours, nil), "1")

    # Exact rather than 0.11: the figure is rounded where it is stored or shown, and not before.
    assert Decimal.equal?(Decimal.round(Day.in_unit(an_hour, :days, nine), 6), "0.111111")
  end

  test "an amount is held as the column will hold it, and may not round away to nothing" do
    filed = fn amount ->
      Day.changeset(%Day{}, %{
        leave_type_id: Ecto.UUID.generate(),
        date: ~D[2026-03-02],
        amount: amount,
        unit: :hours,
        hours_in_day: "8"
      })
    end

    assert Decimal.equal?(Ecto.Changeset.get_change(filed.("0.005"), :amount), "0.01")
    assert errors_on(filed.("0.001")).amount == ["must be greater than 0"]
  end

  test "a day on a date worth no hours is worth nothing in either unit" do
    whole_day = %Day{amount: Decimal.new("1"), unit: :days}
    an_hour = %Day{amount: Decimal.new("4.5"), unit: :hours}
    none = Decimal.new("0")

    assert Decimal.equal?(Day.in_unit(whole_day, :hours, none), "0")
    assert Decimal.equal?(Day.in_unit(an_hour, :days, none), "0")
  end
end
