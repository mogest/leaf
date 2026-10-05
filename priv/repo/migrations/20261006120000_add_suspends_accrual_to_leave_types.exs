defmodule Leaf.Repo.Migrations.AddSuspendsAccrualToLeaveTypes do
  use Ecto.Migration

  def change do
    alter table(:leave_types) do
      add :suspends_accrual, :boolean, null: false, default: false
    end
  end
end
