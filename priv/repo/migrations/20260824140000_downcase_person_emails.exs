defmodule Leaf.Repo.Migrations.DowncasePersonEmails do
  use Ecto.Migration

  # An address is the same address whatever case it was typed in, and Google's claim arrives
  # lowercase, so the column is indexed by what the address is rather than by how it was written.
  def up do
    execute "UPDATE people SET email = lower(email)"

    drop unique_index(:people, [:email])
    create unique_index(:people, ["lower(email)"], name: :people_lower_email_index)
  end

  def down do
    drop unique_index(:people, ["lower(email)"], name: :people_lower_email_index)
    create unique_index(:people, [:email])
  end
end
