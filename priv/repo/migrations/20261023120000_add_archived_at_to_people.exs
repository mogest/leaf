defmodule Leaf.Repo.Migrations.AddArchivedAtToPeople do
  use Ecto.Migration

  def up do
    alter table(:people) do
      add :archived_at, :utc_datetime
    end

    drop unique_index(:people, ["lower(email)"], name: :people_lower_email_index)
    drop unique_index(:people, [:organisation_id, :employee_number])

    create unique_index(:people, ["lower(email)"],
             name: :people_lower_email_index,
             where: "archived_at IS NULL"
           )

    create unique_index(:people, [:organisation_id, :employee_number],
             where: "archived_at IS NULL"
           )
  end

  def down do
    drop unique_index(:people, ["lower(email)"], name: :people_lower_email_index)
    drop unique_index(:people, [:organisation_id, :employee_number])

    create unique_index(:people, ["lower(email)"], name: :people_lower_email_index)
    create unique_index(:people, [:organisation_id, :employee_number])

    alter table(:people) do
      remove :archived_at
    end
  end
end
