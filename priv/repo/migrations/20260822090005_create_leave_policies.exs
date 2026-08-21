defmodule Leaf.Repo.Migrations.CreateLeavePolicies do
  use Ecto.Migration

  def change do
    create table(:leave_types, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :name, :string, null: false
      add :unit, :string, null: false
      add :position, :integer, null: false
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:leave_types, [:organisation_id])

    create table(:leave_policies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :name, :string, null: false
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:leave_policies, [:organisation_id])

    create table(:policy_entitlements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :leave_policy_id, references(:leave_policies, type: :binary_id), null: false
      add :leave_type_id, references(:leave_types, type: :binary_id), null: false
      add :effective_from, :date, null: false
      add :effective_to, :date
      add :granted_to, :date
      add :amount_source, :string, null: false
      add :grant_amount, :decimal, precision: 10, scale: 2
      add :grant_basis, :string
      add :grant_period, :string
      add :grant_timing, :string
      add :pro_rated_by_fte, :boolean, null: false
      add :expiry_rule, :string, null: false
      add :rollover_cap, :decimal, precision: 10, scale: 2
      add :expiry_window_days, :integer
      add :allow_negative, :boolean, null: false
      add :excess_threshold, :decimal, precision: 10, scale: 2

      timestamps(type: :utc_datetime)
    end

    create unique_index(:policy_entitlements, [:leave_policy_id, :leave_type_id, :effective_from],
             name: :policy_entitlements_policy_type_from_index
           )

    create index(:policy_entitlements, [:leave_type_id])

    create table(:person_policy_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :person_id, references(:people, type: :binary_id), null: false
      add :leave_policy_id, references(:leave_policies, type: :binary_id), null: false
      add :effective_from, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:person_policy_assignments, [:person_id, :effective_from])
    create index(:person_policy_assignments, [:leave_policy_id])
  end
end
