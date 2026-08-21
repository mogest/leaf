defmodule Leaf.Repo.Migrations.CreatePeople do
  use Ecto.Migration

  def change do
    create table(:people, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :manager_id, references(:people, type: :binary_id)
      add :name, :string, null: false
      add :email, :string, null: false
      add :google_sub, :string
      add :role, :string, null: false
      add :employment_start_date, :date, null: false
      add :employment_end_date, :date
      add :birth_date, :date

      timestamps(type: :utc_datetime)
    end

    create unique_index(:people, [:email])
    create unique_index(:people, [:google_sub])
    create index(:people, [:organisation_id])
    create index(:people, [:manager_id])

    create table(:person_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :person_id, references(:people, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:person_tokens, [:token])
    create index(:person_tokens, [:person_id])
  end
end
