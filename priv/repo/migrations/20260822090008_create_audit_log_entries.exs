defmodule Leaf.Repo.Migrations.CreateAuditLogEntries do
  use Ecto.Migration

  def change do
    create table(:audit_log_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:people, type: :binary_id)
      add :subject_person_id, references(:people, type: :binary_id)
      add :action, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :binary_id, null: false
      add :changes, :map, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_log_entries, [:actor_id])
    create index(:audit_log_entries, [:subject_person_id])
    create index(:audit_log_entries, [:entity_type, :entity_id])
  end
end
