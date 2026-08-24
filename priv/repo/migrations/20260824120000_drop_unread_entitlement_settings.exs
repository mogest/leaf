defmodule Leaf.Repo.Migrations.DropUnreadEntitlementSettings do
  use Ecto.Migration

  # The rollback gives `allow_negative` a default the original did not have: the column was added
  # to an empty table and there are rows now.
  def change do
    alter table(:policy_entitlements) do
      remove :allow_negative, :boolean, null: false, default: false
      remove :excess_threshold, :decimal, precision: 10, scale: 2
    end
  end
end
