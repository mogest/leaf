defmodule Leaf.Repo.Migrations.CreateMessageDeliveries do
  use Ecto.Migration

  def change do
    create table(:message_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :person_id, references(:people, type: :binary_id), null: false
      add :channel, :string, null: false
      add :topic, :string, null: false
      add :receipt, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:message_deliveries, [:topic])
  end
end
