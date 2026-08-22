defmodule Leaf.Leave.DayTest do
  use ExUnit.Case, async: true

  alias Leaf.Leave.Day

  test "a day converts to the unit asked for, on the hours worked on its date" do
    whole_day = %Day{amount: Decimal.new("1"), unit: :days}
    an_hour = %Day{amount: Decimal.new("1"), unit: :hours}
    nine = Decimal.new("9")

    assert Decimal.equal?(Day.in_unit(whole_day, :hours, nine), "9.00")
    assert Decimal.equal?(Day.in_unit(whole_day, :days, nine), "1")
    assert Decimal.equal?(Day.in_unit(an_hour, :days, nine), "0.11")
    assert Decimal.equal?(Day.in_unit(an_hour, :hours, nil), "1")
  end
end
