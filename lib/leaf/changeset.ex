defmodule Leaf.Changeset do
  @moduledoc "Changeset validators shared across schemas."

  import Ecto.Changeset

  # Every decimal column here is numeric(10, 2) and every integer column a four-byte one.
  @decimal_limits [
    greater_than_or_equal_to: Decimal.new("-99999999.99"),
    less_than_or_equal_to: Decimal.new("99999999.99")
  ]
  @integer_limits [greater_than_or_equal_to: -2_147_483_648, less_than_or_equal_to: 2_147_483_647]

  @doc """
  Errors on `field` where the number is too large for its column to hold.

  Postgres answers an out-of-range number with `22003`, which is not a constraint violation, so
  Ecto cannot turn it into an error on the field and the caller gets a raise naming nothing. This
  is the database's limit rather than the domain's: use it only where the domain has no ceiling of
  its own to state, and state that one instead wherever it does.
  """
  @spec validate_storable(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_storable(changeset, field) do
    validate_number(changeset, field, limits(changeset.types[field]))
  end

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

  defp limits(:decimal), do: @decimal_limits
  defp limits(:integer), do: @integer_limits

  defp ordered(changeset, earlier, later, :gt),
    do: add_error(changeset, later, "must not be before #{earlier}")

  defp ordered(changeset, _earlier, _later, _order), do: changeset

  defp absent(changeset, _field, nil), do: changeset
  defp absent(changeset, field, _value), do: add_error(changeset, field, "must be blank")
end
