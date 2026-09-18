defmodule Leaf.Changeset do
  @moduledoc "Changeset building and validation shared across schemas."

  import Ecto.Changeset, except: [change: 2]

  # Every decimal column here is numeric(10, 2) and every integer column a four-byte one.
  @decimal_limits [
    greater_than_or_equal_to: Decimal.new("-99999999.99"),
    less_than_or_equal_to: Decimal.new("99999999.99")
  ]
  @integer_limits [greater_than_or_equal_to: -2_147_483_648, less_than_or_equal_to: 2_147_483_647]

  @doc """
  The changeset an existing record's form binds to.

  A blank row comes from its context instead, the only place that knows what it hangs off.
  """
  @spec change(struct(), map()) :: Ecto.Changeset.t()
  def change(%mod{} = record, attrs), do: mod.changeset(record, attrs)

  @doc """
  Puts `field` in the form its column will hold it in, and bounds it by `opts` or by the column.

  Both ends go wrong silently otherwise, because the value validated is not the value stored:
  Postgres answers one too large with `22003`, which is not a constraint violation and so cannot be
  turned into an error on the field, and it rounds one too small to zero *after* `greater_than: 0`
  has already passed it. Rounding here is the one rounding — the column would do it anyway, to the
  same half-up rule.

  `opts` are `validate_number/3`'s and narrow the column's own range, which is what is left where
  the domain has no ceiling to state. This is every numeric rule the field has, so nothing else
  reads the value before it is the stored one.
  """
  @spec as_stored(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def as_stored(changeset, field, opts \\ []) do
    type = changeset.types[field]

    changeset
    |> scaled(field, type)
    |> validate_number(field, Keyword.merge(limits(type), opts))
  end

  @doc """
  Errors on `later` when it holds a date earlier than `earlier`.

  Absent dates pass. `:message` in `opts` replaces what is said, for a field whose refusal is read
  somewhere other than under it.
  """
  @spec validate_date_order(Ecto.Changeset.t(), atom(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_date_order(changeset, earlier, later, opts \\ []) do
    case {get_field(changeset, earlier), get_field(changeset, later)} do
      {%Date{} = from, %Date{} = to} ->
        ordered(changeset, earlier, later, Date.compare(from, to), opts)

      _absent ->
        changeset
    end
  end

  @doc "Errors on each of `fields` that holds a value."
  @spec validate_absent(Ecto.Changeset.t(), [atom()]) :: Ecto.Changeset.t()
  def validate_absent(changeset, fields) do
    Enum.reduce(fields, changeset, &absent(&2, &1, get_field(changeset, &1)))
  end

  defp scaled(changeset, field, :decimal), do: update_change(changeset, field, &to_scale/1)
  defp scaled(changeset, _field, :integer), do: changeset

  defp to_scale(nil), do: nil
  defp to_scale(amount), do: Decimal.round(amount, 2)

  defp limits(:decimal), do: @decimal_limits
  defp limits(:integer), do: @integer_limits

  defp ordered(changeset, earlier, later, :gt, opts) do
    add_error(changeset, later, Keyword.get(opts, :message, "must not be before #{earlier}"))
  end

  defp ordered(changeset, _earlier, _later, _order, _opts), do: changeset

  defp absent(changeset, _field, nil), do: changeset
  defp absent(changeset, field, _value), do: add_error(changeset, field, "must be blank")
end
