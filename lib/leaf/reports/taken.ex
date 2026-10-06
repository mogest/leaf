defmodule Leaf.Reports.Taken do
  @moduledoc """
  Approved leave taken over a period, a row per person per leave type, in hours and in days.

  Only the days inside the period count, so a request running over either end counts for its share
  of it. Somebody's country is the one their calendar is in on the period's last day; somebody on no
  calendar then is in no country, and so in no country's report.
  """

  alias Leaf.Leave
  alias Leaf.People
  alias Leaf.Policies
  alias Leaf.Reports.Table

  @columns ["Person", "Country", "Leave type", "Hours", "Days"]

  @doc "The leave taken over `period`, narrowed to a country and a leave type where they are given."
  @spec table(Ecto.UUID.t(), Date.Range.t(), Ecto.UUID.t() | nil, Ecto.UUID.t() | nil) ::
          Table.t()
  def table(organisation_id, period, country_id, leave_type_id) do
    leave_types =
      organisation_id |> Policies.leave_types() |> Enum.filter(&wanted?(&1, leave_type_id))

    people =
      organisation_id
      |> People.employed(period)
      |> Enum.map(&{&1, country(&1, period.last)})
      |> Enum.filter(fn {_person, country} -> wanted?(country, country_id) end)

    approved = Leave.approved(Enum.map(people, &elem(&1, 0)), period)

    taken =
      for {person, country} <- people,
          leave_type <- leave_types,
          days =
            Enum.filter(Map.get(approved, person.id, []), &(&1.leave_type_id == leave_type.id)),
          days != [],
          do: {person, country, leave_type, Leave.worth(person, days)}

    %Table{
      columns: @columns,
      rows:
        for {person, country, leave_type, {:ok, worth}} <- taken do
          [person.name, country && country.name, leave_type.name, worth.hours, worth.days]
        end,
      notes: Table.unmeasured(for {person, _country, _leave_type, :error} <- taken, do: person)
    }
  end

  defp country(person, date) do
    case People.fetch_country_on(person, date) do
      {:ok, country} -> country
      :error -> nil
    end
  end

  defp wanted?(_record, nil), do: true
  defp wanted?(%{id: id}, id), do: true
  defp wanted?(_record, _id), do: false
end
