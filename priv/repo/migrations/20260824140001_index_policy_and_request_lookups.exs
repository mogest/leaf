defmodule Leaf.Repo.Migrations.IndexPolicyAndRequestLookups do
  use Ecto.Migration

  def change do
    create index(:policy_entitlements, [:leave_policy_id])
    create index(:leave_requests, [:status])
  end
end
