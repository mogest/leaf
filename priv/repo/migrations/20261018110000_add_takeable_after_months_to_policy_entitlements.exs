defmodule Leaf.Repo.Migrations.AddTakeableAfterMonthsToPolicyEntitlements do
  use Ecto.Migration

  def change do
    alter table(:policy_entitlements) do
      add :takeable_after_months, :integer
    end
  end
end
