defmodule Leaf.Repo.Migrations.CreateWorkPatterns do
  use Ecto.Migration

  def change do
    create table(:work_patterns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :person_id, references(:people, type: :binary_id), null: false
      add :effective_from, :date, null: false
      add :monday_hours, :decimal, precision: 10, scale: 2, null: false
      add :tuesday_hours, :decimal, precision: 10, scale: 2, null: false
      add :wednesday_hours, :decimal, precision: 10, scale: 2, null: false
      add :thursday_hours, :decimal, precision: 10, scale: 2, null: false
      add :friday_hours, :decimal, precision: 10, scale: 2, null: false
      add :saturday_hours, :decimal, precision: 10, scale: 2, null: false
      add :sunday_hours, :decimal, precision: 10, scale: 2, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:work_patterns, [:person_id, :effective_from])
  end
end
