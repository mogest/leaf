defmodule Leaf.Repo.Migrations.CreateHolidayCalendars do
  use Ecto.Migration

  def change do
    create table(:holiday_calendars, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :name, :string, null: false
      add :country_code, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:holiday_calendars, [:organisation_id])

    create table(:public_holidays, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :holiday_calendar_id,
          references(:holiday_calendars, type: :binary_id, on_delete: :delete_all), null: false

      add :date, :date, null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:public_holidays, [:holiday_calendar_id, :date])

    create table(:person_holiday_calendars, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :person_id, references(:people, type: :binary_id), null: false
      add :holiday_calendar_id, references(:holiday_calendars, type: :binary_id), null: false
      add :effective_from, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:person_holiday_calendars, [:person_id, :effective_from])
    create index(:person_holiday_calendars, [:holiday_calendar_id])
  end
end
