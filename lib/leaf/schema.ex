defmodule Leaf.Schema do
  @moduledoc "Shared schema configuration: UUID primary keys, UTC timestamps, common validators."

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      import Ecto.Changeset
      import Leaf.Changeset

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
