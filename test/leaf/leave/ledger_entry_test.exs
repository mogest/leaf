defmodule Leaf.Leave.LedgerEntryTest do
  use Leaf.DataCase, async: true

  alias Leaf.Leave.LedgerEntry

  @base %{
    person_id: Ecto.UUID.generate(),
    leave_type_id: Ecto.UUID.generate(),
    date: ~D[2026-01-01],
    amount: "8"
  }

  defp changeset(attrs), do: LedgerEntry.changeset(%LedgerEntry{}, Map.merge(@base, attrs))

  test "a grant carries the date its lot lapses" do
    assert changeset(%{kind: :grant, expires_on: ~D[2026-03-31]}).valid?
  end

  test "an accrual into a lapsing period carries the same" do
    assert changeset(%{kind: :accrual, expires_on: ~D[2026-03-31]}).valid?
  end

  test "an imported opening balance may lapse" do
    assert changeset(%{kind: :opening_balance, expires_on: ~D[2026-03-31]}).valid?
  end

  test "an expiry points at the grant it lapsed" do
    assert changeset(%{kind: :expiry, source_entry_id: Ecto.UUID.generate()}).valid?
  end

  test "an expiry does not itself expire" do
    attrs = %{kind: :expiry, expires_on: ~D[2026-03-31]}

    assert errors_on(changeset(attrs)).expires_on == ["must be blank"]
  end

  test "nothing but an expiry points at another entry" do
    attrs = %{kind: :accrual, source_entry_id: Ecto.UUID.generate()}

    assert errors_on(changeset(attrs)).source_entry_id == ["must be blank"]
  end

  test "an adjustment needs a reason" do
    assert errors_on(changeset(%{kind: :adjustment})).reason == ["can't be blank"]
    assert changeset(%{kind: :adjustment, reason: "Opening balance correction"}).valid?
  end

  test "a lot cannot lapse before it is granted" do
    attrs = %{kind: :grant, expires_on: ~D[2025-12-31]}

    assert errors_on(changeset(attrs)).expires_on == ["must not be before date"]
  end
end
