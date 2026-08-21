defmodule Leaf.Repo.Migrations.CreateOrganisations do
  use Ecto.Migration

  def change do
    create table(:organisations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :full_time_week_hours, :decimal, precision: 10, scale: 2, null: false
      add :standard_day_hours, :decimal, precision: 10, scale: 2, null: false
      add :year_start_month, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end
  end
end
