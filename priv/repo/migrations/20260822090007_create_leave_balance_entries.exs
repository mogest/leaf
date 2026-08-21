defmodule Leaf.Repo.Migrations.CreateLeaveBalanceEntries do
  use Ecto.Migration

  def change do
    create table(:leave_balance_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :person_id, references(:people, type: :binary_id), null: false
      add :leave_type_id, references(:leave_types, type: :binary_id), null: false
      add :created_by_id, references(:people, type: :binary_id)
      add :date, :date, null: false
      add :kind, :string, null: false
      add :amount, :decimal, precision: 10, scale: 2, null: false
      add :expires_on, :date
      add :reason, :text

      timestamps(type: :utc_datetime)
    end

    create index(:leave_balance_entries, [:person_id, :leave_type_id])
    create index(:leave_balance_entries, [:leave_type_id])
    create index(:leave_balance_entries, [:created_by_id])
  end
end
