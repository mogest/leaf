defmodule Leaf.Repo.Migrations.AddBalanceCheckToPolicyEntitlements do
  use Ecto.Migration

  def change do
    alter table(:policy_entitlements) do
      add :balance_check, :string, null: false, default: "off"
    end
  end
end
