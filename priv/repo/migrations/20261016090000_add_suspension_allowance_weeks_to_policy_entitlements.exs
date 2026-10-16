defmodule Leaf.Repo.Migrations.AddSuspensionAllowanceWeeksToPolicyEntitlements do
  use Ecto.Migration

  def change do
    alter table(:policy_entitlements) do
      add :suspension_allowance_weeks, :decimal, precision: 10, scale: 2
    end
  end
end
