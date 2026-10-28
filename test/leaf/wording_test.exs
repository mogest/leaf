defmodule Leaf.WordingTest do
  use ExUnit.Case, async: true

  alias Leaf.Wording

  test "hour balances from a working day or half a week read in equal days or uneven weeks" do
    pattern = %Leaf.People.WorkPattern{
      monday_hours: Decimal.new(8),
      tuesday_hours: Decimal.new("8.0"),
      wednesday_hours: Decimal.new(0),
      thursday_hours: Decimal.new(0),
      friday_hours: Decimal.new(0),
      saturday_hours: Decimal.new(0),
      sunday_hours: Decimal.new(0)
    }

    assert Wording.equivalent(Decimal.new(76), :hours, {:ok, pattern}) == "≈ 9.5 days"
    assert Wording.equivalent(Decimal.new(8), :hours, {:ok, pattern}) == "≈ 1 day"
    assert Wording.equivalent(Decimal.new("7.99"), :hours, {:ok, pattern}) == nil
    assert Wording.equivalent(Decimal.new(-8), :hours, {:ok, pattern}) == nil
    assert Wording.equivalent(Decimal.new(0), :hours, {:ok, pattern}) == nil
    assert Wording.equivalent(Decimal.new(76), :days, {:ok, pattern}) == nil
    assert Wording.equivalent(Decimal.new(76), :hours, :error) == nil

    uneven = %{pattern | tuesday_hours: Decimal.new(4)}
    assert Wording.equivalent(Decimal.new(25), :hours, {:ok, uneven}) == "≈ 2.08 weeks"
    assert Wording.equivalent(Decimal.new(12), :hours, {:ok, uneven}) == "≈ 1 week"
    assert Wording.equivalent(Decimal.new(6), :hours, {:ok, uneven}) == "≈ 0.5 weeks"
    assert Wording.equivalent(Decimal.new("5.99"), :hours, {:ok, uneven}) == nil

    empty = %{pattern | monday_hours: Decimal.new(0), tuesday_hours: Decimal.new(0)}
    assert Wording.equivalent(Decimal.new(76), :hours, {:ok, empty}) == nil
  end

  describe "moment/2" do
    test "an instant is read where whoever is reading it is" do
      at = ~U[2026-08-21 21:00:00Z]

      assert Wording.moment(at, "Pacific/Auckland") == "22 August 2026, 09:00"
      assert Wording.moment(at, "Etc/UTC") == "21 August 2026, 21:00"
    end
  end

  describe "date/2" do
    test "an instant falls on the date it is where whoever is reading it is" do
      at = ~U[2026-08-21 21:00:00Z]

      assert Wording.date(at, "Pacific/Auckland") == "22 August 2026"
      assert Wording.date(at, "Etc/UTC") == "21 August 2026"
      assert Wording.brief_date(at, "Pacific/Auckland") == "22 Aug 2026"
      assert Wording.day_and_month(at, "Pacific/Auckland") == "22 August"
    end
  end

  describe "filed/4" do
    test "a request decided before it was brought in says so, having nobody to name" do
      day = %Leaf.Leave.Day{
        date: ~D[2026-08-21],
        amount: Decimal.new(8),
        unit: :hours,
        leave_type: %Leaf.Policies.LeaveType{name: "Annual leave", unit: :hours}
      }

      request = %Leaf.Leave.Request{status: :approved, reviewed_by: nil, days: [day]}

      assert %{progress: "decided before Leaf"} =
               Wording.filed(request, ~D[2026-10-16], "Pacific/Auckland")
    end
  end

  describe "month/2" do
    test "a month in the year being read in is named without it" do
      assert Wording.month(~D[2030-08-01], ~D[2030-02-14]) == "August"
    end

    test "a month in another year is named with it" do
      assert Wording.month(~D[2030-08-01], ~D[2029-02-14]) == "August 2030"
    end
  end
end
