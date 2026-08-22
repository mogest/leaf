defmodule Leaf.Repo.Migrations.CreateLeaveRequests do
  use Ecto.Migration

  def change do
    create table(:leave_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :person_id, references(:people, type: :binary_id), null: false
      add :submitted_by_id, references(:people, type: :binary_id), null: false
      add :reviewed_by_id, references(:people, type: :binary_id)
      add :status, :string, null: false
      add :note, :text
      add :reviewed_at, :utc_datetime
      add :review_comment, :text

      timestamps(type: :utc_datetime)
    end

    create index(:leave_requests, [:person_id])
    create index(:leave_requests, [:submitted_by_id])
    create index(:leave_requests, [:reviewed_by_id])

    create table(:leave_days, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :leave_request_id,
          references(:leave_requests, type: :binary_id, on_delete: :delete_all), null: false

      add :leave_type_id, references(:leave_types, type: :binary_id), null: false
      add :date, :date, null: false
      add :amount, :decimal, precision: 10, scale: 2, null: false
      add :unit, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:leave_days, [:leave_request_id])
    create index(:leave_days, [:leave_type_id])
    create index(:leave_days, [:date])
  end
end
