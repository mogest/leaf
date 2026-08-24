defmodule Leaf.Repo.Migrations.MakeCalendarsRegional do
  use Ecto.Migration

  # A calendar is no longer only a list of holidays: it is a country, or a region within one, and it
  # carries the time zone of whoever is on it. The tables are renamed rather than rebuilt so that
  # every assignment and holiday already recorded survives, and their indexes and constraints go
  # with them so that the names the schemas infer are the names the database holds.
  def change do
    rename table(:holiday_calendars), to: table(:calendars)
    rename table(:person_holiday_calendars), to: table(:person_calendars)
    rename table(:public_holidays), :holiday_calendar_id, to: :calendar_id
    rename table(:person_calendars), :holiday_calendar_id, to: :calendar_id

    rename_index(:holiday_calendars_pkey, :calendars_pkey)
    rename_index(:holiday_calendars_organisation_id_index, :calendars_organisation_id_index)
    rename_index(:person_holiday_calendars_pkey, :person_calendars_pkey)

    rename_index(
      :public_holidays_holiday_calendar_id_date_index,
      :public_holidays_calendar_id_date_index
    )

    rename_index(
      :person_holiday_calendars_person_id_effective_from_index,
      :person_calendars_person_id_effective_from_index
    )

    rename_index(
      :person_holiday_calendars_holiday_calendar_id_index,
      :person_calendars_calendar_id_index
    )

    rename_constraint(
      :calendars,
      :holiday_calendars_organisation_id_fkey,
      :calendars_organisation_id_fkey
    )

    rename_constraint(
      :public_holidays,
      :public_holidays_holiday_calendar_id_fkey,
      :public_holidays_calendar_id_fkey
    )

    rename_constraint(
      :person_calendars,
      :person_holiday_calendars_person_id_fkey,
      :person_calendars_person_id_fkey
    )

    rename_constraint(
      :person_calendars,
      :person_holiday_calendars_holiday_calendar_id_fkey,
      :person_calendars_calendar_id_fkey
    )

    # Nothing observed a zone before this, so UTC is what every existing row was already being read
    # in. New rows say their own, which is why the default does not outlive the backfill.
    alter table(:calendars) do
      add :parent_id, references(:calendars, type: :binary_id)
      add :time_zone, :string, null: false, default: "Etc/UTC"
    end

    alter table(:calendars) do
      modify :time_zone, :string,
        null: false,
        default: nil,
        from: {:string, null: false, default: "Etc/UTC"}
    end

    create index(:calendars, [:parent_id])

    # A calendar is permanent: deleting one took its holidays with it, and every allowance drawn
    # from it would silently recount to zero. Nothing can delete one today, and now nothing can.
    alter table(:public_holidays) do
      modify :calendar_id, references(:calendars, type: :binary_id),
        null: false,
        from: {references(:calendars, type: :binary_id, on_delete: :delete_all), null: false}
    end
  end

  defp rename_index(from, to) do
    execute "ALTER INDEX #{from} RENAME TO #{to}", "ALTER INDEX #{to} RENAME TO #{from}"
  end

  defp rename_constraint(table, from, to) do
    execute "ALTER TABLE #{table} RENAME CONSTRAINT #{from} TO #{to}",
            "ALTER TABLE #{table} RENAME CONSTRAINT #{to} TO #{from}"
  end
end
