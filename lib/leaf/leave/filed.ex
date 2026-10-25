defmodule Leaf.Leave.Filed do
  @moduledoc """
  A person's requests over one of their organisation's financial years, of one leave type or all.

  A request falls in the year its first day does. The years run from the first holding a request to
  the last, and always take in today's, and one outside them reads as the nearer end. The leave
  types are the ones the person has asked for in any year, so choosing one does not change the
  choice; one not among them reads as all of them.
  """

  alias Leaf.Dates
  alias Leaf.Leave.Request
  alias Leaf.Policies.LeaveType

  @type t :: %__MODULE__{
          dates: Date.Range.t(),
          previous: integer() | nil,
          next: integer() | nil,
          leave_types: [LeaveType.t()],
          leave_type_id: Ecto.UUID.t() | nil,
          requests: [Request.t()]
        }

  @enforce_keys [:dates, :previous, :next, :leave_types, :leave_type_id, :requests]
  defstruct @enforce_keys

  @doc "`requests` over the year starting in `start_month` of `year`, or of the one holding `today`."
  @spec new([Request.t()], 1..12, Date.t(), integer() | nil, Ecto.UUID.t() | nil) :: t()
  def new(requests, start_month, today, year, leave_type_id) do
    year_of = &Dates.year_of(&1, start_month)

    {first, last} =
      [today | Enum.map(requests, &first_day/1)] |> Enum.map(year_of) |> Enum.min_max()

    year = (year || year_of.(today)) |> max(first) |> min(last)
    leave_types = leave_types(requests)
    leave_type_id = if Enum.any?(leave_types, &(&1.id == leave_type_id)), do: leave_type_id

    %__MODULE__{
      dates: Dates.year(year, start_month),
      previous: if(year > first, do: year - 1),
      next: if(year < last, do: year + 1),
      leave_types: leave_types,
      leave_type_id: leave_type_id,
      requests:
        Enum.filter(requests, &(year_of.(first_day(&1)) == year and of_type?(&1, leave_type_id)))
    }
  end

  defp first_day(request), do: request.days |> Enum.map(& &1.date) |> Enum.min(Date)

  defp leave_types(requests) do
    requests
    |> Enum.flat_map(& &1.days)
    |> Enum.map(& &1.leave_type)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.position, &1.name})
  end

  defp of_type?(_request, nil), do: true

  defp of_type?(request, leave_type_id),
    do: Enum.any?(request.days, &(&1.leave_type_id == leave_type_id))
end
