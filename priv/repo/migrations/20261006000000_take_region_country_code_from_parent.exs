defmodule Leaf.Repo.Migrations.TakeRegionCountryCodeFromParent do
  use Ecto.Migration

  def up do
    alter table(:calendars) do
      modify :country_code, :string, null: true
    end

    execute "UPDATE calendars SET country_code = NULL WHERE parent_id IS NOT NULL"
  end

  def down do
    execute """
    UPDATE calendars AS region SET country_code = country.country_code
    FROM calendars AS country
    WHERE region.parent_id = country.id
    """

    alter table(:calendars) do
      modify :country_code, :string, null: false
    end
  end
end
