defmodule Leaf.WordingTest do
  use ExUnit.Case, async: true

  alias Leaf.Wording

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

  describe "month/2" do
    test "a month in the year being read in is named without it" do
      assert Wording.month(~D[2030-08-01], ~D[2030-02-14]) == "August"
    end

    test "a month in another year is named with it" do
      assert Wording.month(~D[2030-08-01], ~D[2029-02-14]) == "August 2030"
    end
  end
end
