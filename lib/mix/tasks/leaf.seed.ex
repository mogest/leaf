defmodule Mix.Tasks.Leaf.Seed do
  @shortdoc "Seed an example organisation, New Zealand leave policy and person"
  @moduledoc """
  Seed an example organisation into an empty database.

      mix leaf.seed

  Builds the New Zealand employee policy described in `Leaf.Seed` — annual, sick, quarterly,
  birthday, longevity and bereavement leave — the New Zealand public holiday calendar, and one
  person on that policy.

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

    %{organisation: organisation, person: person} = Seed.run()
    {:ok, pattern} = People.fetch_work_pattern(person, person.employment_start_date)

    Mix.shell().info("""
    Seeded #{organisation.name}.
      #{person.name} <#{person.email}> — started #{person.employment_start_date}, \
    #{People.weekly_hours(pattern)}h a week (#{People.fte(pattern, organisation.full_time_week_hours)} FTE)
    """)
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
