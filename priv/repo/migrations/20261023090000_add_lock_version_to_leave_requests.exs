defmodule Leaf.Repo.Migrations.AddLockVersionToLeaveRequests do
  use Ecto.Migration

  def change do
    alter table(:leave_requests) do
      add :lock_version, :integer, null: false, default: 1
    end
  end
end
