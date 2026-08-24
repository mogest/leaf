defmodule Leaf.Leave.BalanceEntryTest do
  use Leaf.DataCase, async: true

  alias Leaf.Leave.BalanceEntry

  @base %{leave_type_id: Ecto.UUID.generate(), date: ~D[2026-01-01], amount: "8"}

  defp changeset(attrs) do
    BalanceEntry.changeset(
      %BalanceEntry{person_id: Ecto.UUID.generate()},
      Map.merge(@base, attrs)
    )
  end

  test "an imported opening balance may lapse" do
    assert changeset(%{kind: :opening_balance, expires_on: ~D[2026-03-31]}).valid?
  end

  test "an adjustment needs a reason" do
    assert errors_on(changeset(%{kind: :adjustment})).reason == ["can't be blank"]
    assert changeset(%{kind: :adjustment, reason: "Alternative holiday worked 2 January"}).valid?
  end

  test "an adjustment may take a balance down as well as up" do
    attrs = %{kind: :adjustment, amount: "-4", reason: "Duplicate import"}

    assert changeset(attrs).valid?
  end

  test "a figure the column cannot hold is refused rather than raising, either way up" do
    entered = fn amount -> %{kind: :adjustment, amount: amount, reason: "Mistyped import"} end

    assert errors_on(changeset(entered.("1200000000"))).amount == [
             "must be less than or equal to 99999999.99"
           ]

    assert errors_on(changeset(entered.("-1200000000"))).amount == [
             "must be greater than or equal to -99999999.99"
           ]
  end

  test "nothing derived can be entered by hand" do
    assert errors_on(changeset(%{kind: :accrual})).kind == ["is invalid"]
  end

  test "a balance cannot lapse before it arrives" do
    attrs = %{kind: :opening_balance, expires_on: ~D[2025-12-31]}

    assert errors_on(changeset(attrs)).expires_on == ["must not be before date"]
  end
end
