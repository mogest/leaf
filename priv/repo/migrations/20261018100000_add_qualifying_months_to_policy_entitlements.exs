defmodule Leaf.Repo.Migrations.AddQualifyingMonthsToPolicyEntitlements do
  use Ecto.Migration

  def change do
    alter table(:policy_entitlements) do
      add :qualifying_months, :integer
    end
  end
end
