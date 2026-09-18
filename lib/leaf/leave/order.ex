defmodule Leaf.Leave.Order do
  @moduledoc """
  What a request asks for: a leave type, a stretch of dates, and how much of the day.

  An instruction rather than the days themselves, which the work pattern decides — `days_for/2` on
  the context works them out. Nothing here is stored, so this holds what §5.2 says somebody may ask
  for and holds it once, for a form and for anything else that asks.

  The two dates are one span: a last day left blank asks for the first day on its own, and somebody
  still in the first field has not left the last one out. A blank amount asks for the whole of each
  day, which is a day whatever the leave type counts in. An amount given is hours, because hours are
  what somebody can count — nobody knows offhand what 0.4 of a nine-hour Wednesday is — and hours
  are a thing about one day, so a stretch cannot be asked for in them.

  A refusal is read in a list of them rather than under the field it is about, so each one is a
  sentence that stands on its own.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Leaf.Changeset

  @type t :: %__MODULE__{}

  @fields [:leave_type_id, :from, :to, :amount, :note]

  @invalid %{
    leave_type_id: "Choose a leave type.",
    from: "Give a first day.",
    to: "Give a last day.",
    amount: "The hours off have to be a number."
  }

  @primary_key false
  embedded_schema do
    field :leave_type_id, Ecto.UUID
    field :from, :date
    field :to, :date
    field :amount, :decimal
    field :unit, Ecto.Enum, values: [:hours, :days]
    field :note, :string
    field :span, :any, virtual: true
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(order, attrs) do
    order
    |> cast(attrs, @fields, message: &invalid/2)
    |> validate_date_order(:from, :to, message: "The last day comes before the first.")
    |> spanning()
    |> measured()
    |> as_stored(:amount, greater_than: 0, message: "The hours off have to be more than nothing.")
    |> one_day()
  end

  defp invalid(field, _meta), do: @invalid[field]

  defp spanning(changeset) do
    put_change(changeset, :span, spanned(get_field(changeset, :from), get_field(changeset, :to)))
  end

  defp spanned(nil, nil), do: nil
  defp spanned(from, to), do: bounded(from || to, to || from)

  # Dates the wrong way round span nothing, which is what stops anything being asked over a stretch
  # that does not exist. What is wrong with them is already said, against the last day.
  defp bounded(first, last) do
    case Date.after?(first, last) do
      true -> nil
      false -> Date.range(first, last)
    end
  end

  # A blank amount is said to be days and left blank: a whole day put in it is a figure the form
  # would show back in a field nobody typed into. What a day of it comes to is `days_for/2`'s.
  defp measured(changeset) do
    put_change(changeset, :unit, unit(get_change(changeset, :amount)))
  end

  defp unit(nil), do: :days
  defp unit(_hours), do: :hours

  defp one_day(changeset) do
    asked_of(changeset, get_field(changeset, :unit), get_field(changeset, :span))
  end

  defp asked_of(changeset, :hours, %Date.Range{first: date, last: date}), do: changeset

  defp asked_of(changeset, :hours, %Date.Range{}) do
    add_error(changeset, :amount, "Hours off can only be asked of a single day.")
  end

  defp asked_of(changeset, _unit, _span), do: changeset
end
