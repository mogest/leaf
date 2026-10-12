defmodule Leaf.Repo.Migrations.DropGoogleSubAndPersonTokens do
  use Ecto.Migration

  def up do
    drop table(:person_tokens)
    drop unique_index(:people, [:google_sub])

    alter table(:people) do
      remove :google_sub
    end
  end

  def down do
    alter table(:people) do
      add :google_sub, :string
    end

    create unique_index(:people, [:google_sub])

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
