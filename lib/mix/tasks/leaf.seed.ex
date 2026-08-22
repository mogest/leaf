defmodule Mix.Tasks.Leaf.Seed do
  @shortdoc "Seed an example organisation, New Zealand leave policy and person"
  @moduledoc """
  Seed an example organisation into an empty database.

      mix leaf.seed

  Builds the two New Zealand policies described in `Leaf.Seed` — an employee one carrying annual,
  sick, quarterly, birthday, longevity and bereavement leave, and a contractor hybrid that is
  credited its share of the public holidays instead of taking them off — the New Zealand public
  holiday calendar, and somebody on each policy.

  Refuses to run where an organisation already exists, since it is meant for a fresh local
  database. Use `mix ecto.reset` first.
  """

  use Mix.Task

  alias Leaf.Org
  alias Leaf.People
  alias Leaf.Seed

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    refuse_if_seeded()

    %{organisation: organisation, people: people} = Seed.run()

    Mix.shell().info("Seeded #{organisation.name}.")

    people
    |> Map.values()
    |> Enum.sort_by(& &1.employment_start_date, Date)
    |> Enum.each(&Mix.shell().info(describe(&1, organisation)))
  end

  defp describe(person, organisation) do
    {:ok, pattern} = People.fetch_work_pattern(person, person.employment_start_date)
    weekly_hours = People.weekly_hours(pattern)
    fte = People.fte(pattern, organisation.full_time_week_hours)

    "  #{person.name} <#{person.email}> — started #{person.employment_start_date}, " <>
      "#{weekly_hours}h a week (#{fte} FTE)"
  end

  defp refuse_if_seeded do
    case Org.organisations() do
      [] ->
        :ok

      [organisation | _rest] ->
        Mix.raise("#{organisation.name} is already seeded; run mix ecto.reset first")
    end
  end
end
