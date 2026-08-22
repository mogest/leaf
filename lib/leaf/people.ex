defmodule Leaf.People do
  @moduledoc """
  People, and the effective-dated facts that follow them.

  A person's work pattern, leave policy and holiday calendar each change over time, so most
  questions here are asked either of a single date or of a span. A span comes back as segments —
  one per stretch over which the answer holds — which is what anything working out entitlement
  needs, since a mid-year change splits the year rather than replacing it.

  A `Person` and a `WorkPattern` are values other areas hold and read; the policy and the calendar
  belong to other areas, so those come back as ids to look up there rather than as assignment rows.

  Everything effective-dated here can be amended or removed after the fact (§4.4). A superseding
  row is how a change from a date is recorded; amending and deleting are how a row that should
  never have been written is put right, and every balance that leant on it follows.

  Every change is recorded against the person it is about, bar a person's own creation: until they
  exist there is nobody for it to be about.
  """

  import Ecto.Query

  alias Leaf.Audit
  alias Leaf.Org.Organisation
  alias Leaf.People.Person
  alias Leaf.People.PersonHolidayCalendar
  alias Leaf.People.PersonPolicyAssignment
  alias Leaf.People.Timeline
  alias Leaf.People.WorkPattern
  alias Leaf.Repo

  @typedoc "A stretch of dates over which one answer holds."
  @type segment(value) :: {Date.Range.t(), value}

  @doc "Creates a person."
  @spec create_person(Organisation.t(), Person.t() | nil, map()) :: Audit.written(Person.t())
  def create_person(organisation, actor, attrs) do
    %Person{organisation_id: organisation.id}
    |> Person.changeset(attrs)
    |> Audit.write("person.created", actor)
  end

  @doc """
  Amends a person.

  Correcting an employment start date moves every anniversary that hangs off it, so this is the
  one edit here that can re-work a whole entitlement history on its own.
  """
  @spec update_person(Person.t(), Person.t() | nil, map()) :: Audit.written(Person.t())
  def update_person(person, actor, attrs) do
    person |> Person.changeset(attrs) |> Audit.write("person.updated", actor)
  end

  @doc "The person, or `:error` where no such person exists."
  @spec fetch_person(Ecto.UUID.t()) :: {:ok, Person.t()} | :error
  def fetch_person(id) do
    case Repo.get(Person, id) do
      nil -> :error
      person -> {:ok, person}
    end
  end

  @doc "Puts a person on a work pattern from a date, superseding whatever they were on."
  @spec create_work_pattern(Person.t(), Person.t() | nil, map()) :: Audit.written(WorkPattern.t())
  def create_work_pattern(person, actor, attrs) do
    %WorkPattern{person_id: person.id}
    |> WorkPattern.changeset(attrs)
    |> Audit.write("work_pattern.created", actor, person.id)
  end

  @doc "Corrects a work pattern, including the date it took effect."
  @spec update_work_pattern(WorkPattern.t(), Person.t() | nil, map()) ::
          Audit.written(WorkPattern.t())
  def update_work_pattern(work_pattern, actor, attrs) do
    work_pattern
    |> WorkPattern.changeset(attrs)
    |> Audit.write("work_pattern.updated", actor, work_pattern.person_id)
  end

  @doc """
  Removes a work pattern, letting whatever preceded it run on.

  Removing the first leaves the person with no hours before the next one, which anything working
  out entitlement over that stretch will refuse rather than read as zero.
  """
  @spec delete_work_pattern(WorkPattern.t(), Person.t() | nil) :: Audit.written(WorkPattern.t())
  def delete_work_pattern(work_pattern, actor) do
    Audit.delete(work_pattern, "work_pattern.deleted", actor, work_pattern.person_id)
  end

  @doc "Puts a person on a leave policy from a date."
  @spec create_policy_assignment(Person.t(), Person.t() | nil, map()) ::
          Audit.written(PersonPolicyAssignment.t())
  def create_policy_assignment(person, actor, attrs) do
    %PersonPolicyAssignment{person_id: person.id}
    |> PersonPolicyAssignment.changeset(attrs)
    |> Audit.write("policy_assignment.created", actor, person.id)
  end

  @doc "Corrects which policy a person was on, or from when."
  @spec update_policy_assignment(PersonPolicyAssignment.t(), Person.t() | nil, map()) ::
          Audit.written(PersonPolicyAssignment.t())
  def update_policy_assignment(assignment, actor, attrs) do
    assignment
    |> PersonPolicyAssignment.changeset(attrs)
    |> Audit.write("policy_assignment.updated", actor, assignment.person_id)
  end

  @doc "Removes a policy assignment, letting whatever preceded it run on."
  @spec delete_policy_assignment(PersonPolicyAssignment.t(), Person.t() | nil) ::
          Audit.written(PersonPolicyAssignment.t())
  def delete_policy_assignment(assignment, actor) do
    Audit.delete(assignment, "policy_assignment.deleted", actor, assignment.person_id)
  end

  @doc "Puts a person on a holiday calendar from a date."
  @spec create_calendar_assignment(Person.t(), Person.t() | nil, map()) ::
          Audit.written(PersonHolidayCalendar.t())
  def create_calendar_assignment(person, actor, attrs) do
    %PersonHolidayCalendar{person_id: person.id}
    |> PersonHolidayCalendar.changeset(attrs)
    |> Audit.write("calendar_assignment.created", actor, person.id)
  end

  @doc "Corrects which calendar a person observed, or from when."
  @spec update_calendar_assignment(PersonHolidayCalendar.t(), Person.t() | nil, map()) ::
          Audit.written(PersonHolidayCalendar.t())
  def update_calendar_assignment(assignment, actor, attrs) do
    assignment
    |> PersonHolidayCalendar.changeset(attrs)
    |> Audit.write("calendar_assignment.updated", actor, assignment.person_id)
  end

  @doc "Removes a calendar assignment, letting whatever preceded it run on."
  @spec delete_calendar_assignment(PersonHolidayCalendar.t(), Person.t() | nil) ::
          Audit.written(PersonHolidayCalendar.t())
  def delete_calendar_assignment(assignment, actor) do
    Audit.delete(assignment, "calendar_assignment.deleted", actor, assignment.person_id)
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

  @doc """
  The hours the person works on each date in `range`, in order.

  Refuses a range they have no pattern over part of, for the reason `work_pattern_segments!/2`
  does: a date nobody knows the hours of is not a date they worked none.
  """
  @spec hours_per_day(Person.t(), Date.Range.t()) :: [{Date.t(), Decimal.t()}]
  def hours_per_day(person, range) do
    person
    |> work_pattern_segments!(range)
    |> Enum.flat_map(fn {span, pattern} -> Enum.map(span, &{&1, hours_on(pattern, &1)}) end)
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
