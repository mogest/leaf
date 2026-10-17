defmodule Leaf.Repo.Migrations.AddObservedOnToPublicHolidays do
  use Ecto.Migration

  def change do
    alter table(:public_holidays) do
      add :observed_on, :date
    end
  end
end
