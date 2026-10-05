defmodule Leaf.Repo.Migrations.IndexUniqueLeaveDays do
  use Ecto.Migration

  def change do
    create unique_index(:leave_days, [:leave_request_id, :date, :leave_type_id])
  end
end
