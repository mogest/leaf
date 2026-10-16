defmodule Leaf.Repo.Migrations.AddNeedsApprovalToLeaveTypes do
  use Ecto.Migration

  def change do
    alter table(:leave_types) do
      add :needs_approval, :boolean, null: false, default: true
    end

    alter table(:leave_requests) do
      add :approved_on_filing, :boolean, null: false, default: false
    end
  end
end
