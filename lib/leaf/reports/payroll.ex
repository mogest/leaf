defmodule Leaf.Reports.Payroll do
  @moduledoc """
  Approved leave as iPayroll's Leave Requests upload takes it, each row a request it adds as pending.

  A request belongs to the period its first day falls in and goes whole, so periods laid end to end
  send each one exactly once. A request drawing on more than one leave type goes as a row a type,
  since a row names one. iPayroll refuses Days on leave it counts in hours, so Days is filled only
  for a type kept in days.

  Leave of a type with no payroll code has nothing to go under and is left out, and somebody with
  no employee number goes with a blank one, for the upload to refuse rather than for their leave to go
  missing. Leave no work pattern covers cannot be counted, so it is left out too. The notes say
  which.

  Narrowed by country or leave policy, a request goes by the one its person is in on its first day,
  and somebody in none then is left out.
  """

  alias Leaf.Leave
  alias Leaf.People
  alias Leaf.Reports.Table

  @columns ["Id", "Name", "Leave Type", "First Day", "Last Day", "Hours", "Days", "Reason"]

  @doc "The upload for the organisation's requests whose first day falls in `period`, narrowed where asked."
  @spec table(Ecto.UUID.t(), Date.Range.t(), Ecto.UUID.t() | nil, Ecto.UUID.t() | nil) ::
          Table.t()
  def table(organisation_id, period, country_id, leave_policy_id) do
    {coded, uncoded} =
      organisation_id
      |> Leave.approved_starting(period)
      |> narrow(country_id, &People.fetch_country_on/2)
      |> narrow(leave_policy_id, &People.fetch_leave_policy_on/2)
      |> Enum.flat_map(&by_type/1)
      |> Enum.split_with(fn {_request, leave_type, _days} -> leave_type.payroll_code end)

    {measured, unmeasured} =
      coded
      |> Enum.map(fn {request, _leave_type, days} = line ->
        {line, Leave.worth(request.person, days)}
      end)
      |> Enum.split_with(&match?({_line, {:ok, _worth}}, &1))

    %Table{
      columns: @columns,
      rows: Enum.map(measured, &row/1),
      notes:
        uncoded_notes(uncoded) ++
          unidentified_notes(measured) ++
          Table.unmeasured(
            for {{request, _type, _days}, :error} <- unmeasured, do: request.person
          )
    }
  end

  defp narrow(requests, nil, _fetch_on), do: requests

  defp narrow(requests, id, fetch_on) do
    Enum.filter(requests, fn request ->
      first_day = request.days |> Enum.map(& &1.date) |> Enum.min(Date)
      match?({:ok, %{id: ^id}}, fetch_on.(request.person, first_day))
    end)
  end

  defp by_type(request) do
    request.days
    |> Enum.group_by(& &1.leave_type)
    |> Enum.sort_by(fn {leave_type, _days} -> leave_type.position end)
    |> Enum.map(fn {leave_type, days} -> {request, leave_type, days} end)
  end

  defp row({{%{person: person} = request, leave_type, days}, {:ok, worth}}) do
    dates = Enum.map(days, & &1.date)

    [
      person.employee_number,
      person.name,
      leave_type.payroll_code,
      Enum.min(dates, Date),
      Enum.max(dates, Date),
      worth.hours,
      if(leave_type.unit == :days, do: worth.days),
      request.note
    ]
  end

  defp uncoded_notes(uncoded) do
    uncoded
    |> Enum.group_by(fn {_request, leave_type, _days} -> leave_type end, &elem(&1, 0))
    |> Enum.sort_by(fn {leave_type, _requests} -> leave_type.position end)
    |> Enum.map(fn {leave_type, requests} ->
      "#{leave_type.name} has no payroll code, so it is left out of #{counted(requests)}."
    end)
  end

  defp unidentified_notes(measured) do
    unidentified =
      for {{%{person: %{employee_number: nil} = person}, _leave_type, _days}, _worth} <- measured,
          uniq: true,
          do: person

    case unidentified do
      [] ->
        []

      [person] ->
        ["#{person.name} has no employee number, so the Id on their rows is blank."]

      people ->
        ["#{length(people)} people have no employee number, so the Id on their rows is blank."]
    end
  end

  defp counted(requests) do
    case requests |> Enum.uniq_by(& &1.id) |> length() do
      1 -> "1 request"
      count -> "#{count} requests"
    end
  end
end
