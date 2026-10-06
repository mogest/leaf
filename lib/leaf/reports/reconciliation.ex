defmodule Leaf.Reports.Reconciliation do
  @moduledoc """
  What changed in a pay period's leave after a payroll run: a row a change, oldest first.

  A change made after the end of the cut-off date, where the reader is, is one the run did not see.
  Each row shows the request as it stands now, so a request changed twice reads the same twice
  with what happened to it each time. When it happened is kept in UTC, for whoever shows it to say
  in the reader's zone.
  """

  alias Leaf.Leave
  alias Leaf.Reports.Table

  @columns [
    "When",
    "Change",
    "Person",
    "Leave type",
    "First day",
    "Last day",
    "Hours",
    "Days",
    "Status now"
  ]

  @changes %{requested: "Filed", amended: "Amended", approved: "Approved", cancelled: "Cancelled"}

  @doc "The changes to leave in `period` made after `cut_off` was over in `zone`."
  @spec table(Ecto.UUID.t(), Date.Range.t(), Date.t(), String.t()) :: Table.t()
  def table(organisation_id, period, cut_off, zone) do
    since = cut_off |> Date.add(1) |> midnight(zone) |> DateTime.shift_zone!("Etc/UTC")

    changes =
      for {request, change, at} <- Leave.revisions(organisation_id, period, since),
          do: {request, change, at, Leave.worth(request.person, request.days)}

    rows =
      for {request, change, at, {:ok, worth}} <- changes do
        dates = Enum.map(request.days, & &1.date)

        [
          at,
          @changes[change],
          request.person.name,
          request.days |> Enum.map(& &1.leave_type.name) |> Enum.uniq() |> Enum.join(", "),
          Enum.min(dates, Date),
          Enum.max(dates, Date),
          worth.hours,
          worth.days,
          to_string(request.status)
        ]
      end

    %Table{
      columns: @columns,
      rows: rows,
      notes: Table.unmeasured(for {request, _change, _at, :error} <- changes, do: request.person)
    }
  end

  # A zone that moves its clocks at midnight has a day with no midnight, or with two.
  defp midnight(date, zone) do
    case DateTime.new(date, ~T[00:00:00], zone) do
      {:ok, at} -> at
      {:gap, _before, starts} -> starts
      {:ambiguous, first, _second} -> first
    end
  end
end
