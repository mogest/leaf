defmodule Leaf.Repo.Migrations.AddPayrollIdentifiers do
  use Ecto.Migration

  def change do
    alter table(:people) do
      add :employee_number, :string
    end

    alter table(:leave_types) do
      add :payroll_code, :string
    end

    create unique_index(:people, [:organisation_id, :employee_number])
  end
end
