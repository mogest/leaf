defmodule LeafWeb.WordingTest do
  use ExUnit.Case, async: true

  alias LeafWeb.Wording

  describe "month/2" do
    test "a month in the year being read in is named without it" do
      assert Wording.month(~D[2030-08-01], ~D[2030-02-14]) == "August"
    end

    test "a month in another year is named with it" do
      assert Wording.month(~D[2030-08-01], ~D[2029-02-14]) == "August 2030"
    end
  end
end
