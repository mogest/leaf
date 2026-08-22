defmodule Leaf.People do
  @moduledoc """
  People, and the effective-dated facts that follow them.

  A person's work pattern, leave policy and holiday calendar each change over time, so most
  questions here are asked either of a single date or of a span. A span comes back as segments —
  one per stretch over which the answer holds — which is what anything working out entitlement
  needs, since a mid-year change splits the year rather than replacing it.

  A `Person` and a `WorkPattern` are values other areas hold and read; the policy and the calendar
  belong to other areas, so those come back as ids to look up there rather than as assignment rows.
  """

  import Ecto.Query

  alias Leaf.People.Person
  alias Leaf.People.PersonHolidayCalendar
  alias Leaf.People.PersonPolicyAssignment
  alias Leaf.People.Timeline
  alias Leaf.People.WorkPattern
  alias Leaf.Repo

  @typedoc "A stretch of dates over which one answer holds."
  @type segment(value) :: {Date.Range.t(), value}

  @doc "Creates a person."
  @spec create_person(map()) :: {:ok, Person.t()} | {:error, Ecto.Changeset.t()}
  def create_person(attrs), do: %Person{} |> Person.changeset(attrs) |> Repo.insert()

  @doc "The person, or `:error` where no such person exists."
  @spec fetch_person(Ecto.UUID.t()) :: {:ok, Person.t()} | :error
  def fetch_person(id) do
    case Repo.get(Person, id) do
      nil -> :error
      person -> {:ok, person}
    end
  end

  @doc "Puts a person on a work pattern from a date, superseding whatever they were on."
  @spec create_work_pattern(map()) :: {:ok, WorkPattern.t()} | {:error, Ecto.Changeset.t()}
  def create_work_pattern(attrs) do
    %WorkPattern{} |> WorkPattern.changeset(attrs) |> Repo.insert()
  end

  @doc "Puts a person on a leave policy from a date."
  @spec assign_leave_policy(map()) ::
          {:ok, PersonPolicyAssignment.t()} | {:error, Ecto.Changeset.t()}
  def assign_leave_policy(attrs) do
    %PersonPolicyAssignment{} |> PersonPolicyAssignment.changeset(attrs) |> Repo.insert()
  end

  @doc "Puts a person on a holiday calendar from a date."
  @spec assign_holiday_calendar(map()) ::
          {:ok, PersonHolidayCalendar.t()} | {:error, Ecto.Changeset.t()}
  def assign_holiday_calendar(attrs) do
    %PersonHolidayCalendar{} |> PersonHolidayCalendar.changeset(attrs) |> Repo.insert()
  end

  @doc """
  The work pattern a person is on `date`.

  `:error` before their first pattern takes effect.
  """
  @spec fetch_work_pattern(Person.t(), Date.t()) :: {:ok, WorkPattern.t()} | :error
  def fetch_work_pattern(person, date) do
    person |> succession(WorkPattern) |> Timeline.fetch(date)
  end

  @doc "Each work pattern the person is on over part of `range`, with the span it covers."
  @spec work_pattern_segments(Person.t(), Date.Range.t()) :: [segment(WorkPattern.t())]
  def work_pattern_segments(person, range) do
    person |> succession(WorkPattern) |> Timeline.segments(range)
  end

  @doc """
  The same, refusing a `range` the person has no pattern over part of.

  Hours nobody knows cannot be pro-rated, so anything working out entitlement wants this rather
  than a partial answer: a stretch a person has no pattern for is a hole in the record, not a zero.
  """
  @spec work_pattern_segments!(Person.t(), Date.Range.t()) :: [segment(WorkPattern.t())]
  def work_pattern_segments!(person, range) do
    person |> work_pattern_segments(range) |> covering!(range, person, "work pattern")
  end

  @doc "The id of the leave policy the person is on over each part of `range`."
  @spec leave_policy_segments(Person.t(), Date.Range.t()) :: [segment(Ecto.UUID.t())]
  def leave_policy_segments(person, range) do
    person
    |> succession(PersonPolicyAssignment)
    |> Timeline.segments(range)
    |> Enum.map(fn {span, assignment} -> {span, assignment.leave_policy_id} end)
  end

  @doc "The id of the holiday calendar the person observes over each part of `range`."
  @spec holiday_calendar_segments(Person.t(), Date.Range.t()) :: [segment(Ecto.UUID.t())]
  def holiday_calendar_segments(person, range) do
    person
    |> succession(PersonHolidayCalendar)
    |> Timeline.segments(range)
    |> Enum.map(fn {span, assignment} -> {span, assignment.holiday_calendar_id} end)
  end

  @doc "The same, refusing a `range` the person observes no calendar over part of."
  @spec holiday_calendar_segments!(Person.t(), Date.Range.t()) :: [segment(Ecto.UUID.t())]
  def holiday_calendar_segments!(person, range) do
    person |> holiday_calendar_segments(range) |> covering!(range, person, "holiday calendar")
  end

  @doc "The hours worked over a full week under a work pattern."
  @spec weekly_hours(WorkPattern.t()) :: Decimal.t()
  defdelegate weekly_hours(work_pattern), to: WorkPattern

  @doc "The hours worked on `date` under a work pattern."
  @spec hours_on(WorkPattern.t(), Date.t()) :: Decimal.t()
  defdelegate hours_on(work_pattern, date), to: WorkPattern

  @doc "Whether any hours are worked on `date` under a work pattern."
  @spec working_day?(WorkPattern.t(), Date.t()) :: boolean()
  defdelegate working_day?(work_pattern, date), to: WorkPattern

  @doc "The fraction of the organisation's full-time week a work pattern works, for display."
  @spec fte(WorkPattern.t(), Decimal.t()) :: Decimal.t()
  defdelegate fte(work_pattern, full_time_week_hours), to: WorkPattern

  defp succession(person, schema) do
    Repo.all(from row in schema, where: row.person_id == ^person.id)
  end

  # A succession has no gaps of its own — each row holds until the next supersedes it — so the only
  # stretch of a range that can be missing is the one before its first row takes effect.
  defp covering!([{%{first: first}, _row} | _rest] = segments, %{first: first}, _person, _what) do
    segments
  end

  defp covering!(_segments, range, person, what) do
    raise "#{person.name} (#{person.id}) has no #{what} in force on #{range.first}"
  end
end
