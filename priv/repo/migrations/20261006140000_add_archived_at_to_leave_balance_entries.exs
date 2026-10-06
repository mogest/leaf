defmodule Leaf.Repo.Migrations.AddArchivedAtToLeaveBalanceEntries do
  use Ecto.Migration

  def change do
    alter table(:leave_balance_entries) do
      add :archived_at, :utc_datetime
    end
  end
end
