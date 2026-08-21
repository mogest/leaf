defmodule Leaf.Changeset do
  @moduledoc "Changeset validators shared across schemas."

  import Ecto.Changeset

  @doc """
  Errors on `later` when it holds a date earlier than `earlier`.

  Absent dates pass.
  """
  @spec validate_date_order(Ecto.Changeset.t(), atom(), atom()) :: Ecto.Changeset.t()
  def validate_date_order(changeset, earlier, later) do
    case {get_field(changeset, earlier), get_field(changeset, later)} do
      {%Date{} = from, %Date{} = to} -> ordered(changeset, earlier, later, Date.compare(from, to))
      _ -> changeset
    end
  end

  @doc "Errors on each of `fields` that holds a value."
  @spec validate_absent(Ecto.Changeset.t(), [atom()]) :: Ecto.Changeset.t()
  def validate_absent(changeset, fields) do
    Enum.reduce(fields, changeset, &absent(&2, &1, get_field(changeset, &1)))
  end

  defp ordered(changeset, earlier, later, :gt),
    do: add_error(changeset, later, "must not be before #{earlier}")

  defp ordered(changeset, _earlier, _later, _order), do: changeset

  defp absent(changeset, _field, nil), do: changeset
  defp absent(changeset, field, _value), do: add_error(changeset, field, "must be blank")
end
