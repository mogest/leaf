defmodule Leaf.Leave.Order do
  @moduledoc """
  What a request asks for: a leave type, a stretch of dates, and how much of the day.

  An instruction rather than the days themselves, which the work pattern decides — `days_for/2` on
  the context works them out. Nothing here is stored, so this holds what §5.2 says somebody may ask
  for and holds it once, for a form and for anything else that asks.

  The two dates are one span: a last day left blank asks for the first day on its own, and somebody
  still in the first field has not left the last one out. A blank amount asks for the whole of each
  day, which is a day whatever the leave type counts in. An amount given is part of one day, counted
  in the leave type's own unit — half a day of sick leave, three hours of annual — so a stretch
  cannot be asked for in it.

  A refusal is read in a list of them rather than under the field it is about, so each one is a
  sentence that stands on its own.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Leaf.Changeset

  alias Leaf.Leave.Day

  @type t :: %__MODULE__{}

  @fields [:leave_type_id, :from, :to, :amount, :note]

  @invalid %{
    leave_type_id: "Choose a leave type.",
    from: "Give a first day.",
    to: "Give a last day.",
    amount: "The time off has to be a number."
  }

  @primary_key false
  embedded_schema do
    field :leave_type_id, Ecto.UUID
    field :from, :date
    field :to, :date
    field :amount, :decimal
    field :counted_in, Ecto.Enum, values: [:hours, :days], virtual: true
    field :note, :string
    field :span, :any, virtual: true
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(order, attrs) do
    order
    |> cast(attrs, @fields, message: &invalid/2)
    |> validate_date_order(:from, :to, message: "The last day comes before the first.")
    |> validate_length(:note, max: 1000, message: "A note can be at most 1,000 characters.")
    |> within_reach()
    |> spanning()
    |> measured()
    |> as_stored(:amount, greater_than: 0, message: "The time off has to be more than nothing.")
    |> one_day()
  end

  defp invalid(field, _meta), do: @invalid[field]

  defp within_reach(changeset) do
    reach(changeset, get_field(changeset, :from), get_field(changeset, :to))
  end

  defp reach(changeset, %Date{} = from, %Date{} = to) do
    case Date.after?(to, Date.shift(from, year: 2)) do
      true -> add_error(changeset, :to, "Leave can be asked for at most two years at a time.")
      false -> changeset
    end
  end

  defp reach(changeset, _from, _to), do: changeset

  # Refused dates span nothing, which is what stops anything being asked over a stretch that does
  # not exist or is too long to walk. What is wrong with them is already said, against the last day.
  defp spanning(changeset) do
    from = get_field(changeset, :from)
    to = get_field(changeset, :to)

    put_change(changeset, :span, spanned(changeset.errors[:to], from, to))
  end

  defp spanned(_refused, nil, nil), do: nil
  defp spanned(nil, from, to), do: Date.range(from || to, to || from)
  defp spanned(_refused, _from, _to), do: nil

  defp measured(changeset) do
    put_change(changeset, :counted_in, Day.counted_in(get_field(changeset, :leave_type_id)))
  end

  defp one_day(changeset) do
    asked_of(changeset, get_field(changeset, :amount), get_field(changeset, :span))
  end

  defp asked_of(changeset, nil, _span), do: changeset
  defp asked_of(changeset, _amount, %Date.Range{first: date, last: date}), do: changeset

  defp asked_of(changeset, _amount, %Date.Range{}) do
    add_error(changeset, :amount, "Part of a day can only be asked of a single day.")
  end

  defp asked_of(changeset, _amount, _span), do: changeset
end
