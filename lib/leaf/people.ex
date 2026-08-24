defmodule Leaf.People do
  @moduledoc """
  People, and the effective-dated facts that follow them.

  A person's work pattern, leave policy and calendar each change over time, so most questions here
  are asked either of a single date or of a span. A span comes back as segments — one per stretch
  over which the answer holds — which is what anything working out entitlement needs, since a
  mid-year change splits the year rather than replacing it.

  A `Person` and a `WorkPattern` are values other areas hold and read; the policy and the calendar
  belong to other areas, so what those answer is what the person's record says of them — which
  holidays they observe, what zone they are in — rather than the assignment rows themselves.

  Everything effective-dated here can be amended or removed after the fact (§4.4). A superseding
  row is how a change from a date is recorded; amending and deleting are how a row that should
  never have been written is put right, and every balance that leant on it follows.

  Every change is recorded against the person it is about, bar a person's own creation: until they
  exist there is nobody for it to be about.
  """

  import Ecto.Query

  alias Leaf.Audit
  alias Leaf.Org
  alias Leaf.Org.Organisation
  alias Leaf.Org.PublicHoliday
  alias Leaf.People.Person
  alias Leaf.People.PersonCalendar
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
  The changeset a person's form binds to: a new one for the organisation, or an existing one.

  Every context here offers the same pair, so a form never reaches for a schema itself.
  """
  @spec change_person(Organisation.t() | Person.t(), map()) :: Ecto.Changeset.t()
  def change_person(%Organisation{} = organisation, attrs) do
    Person.changeset(%Person{organisation_id: organisation.id}, attrs)
  end

  def change_person(%Person{} = person, attrs), do: Person.changeset(person, attrs)

  @doc "The changeset a work pattern's form binds to."
  @spec change_work_pattern(Person.t() | WorkPattern.t(), map()) :: Ecto.Changeset.t()
  def change_work_pattern(%Person{} = person, attrs) do
    WorkPattern.changeset(%WorkPattern{person_id: person.id}, attrs)
  end

  def change_work_pattern(%WorkPattern{} = pattern, attrs),
    do: WorkPattern.changeset(pattern, attrs)

  @doc "The changeset a policy assignment's form binds to."
  @spec change_policy_assignment(Person.t() | PersonPolicyAssignment.t(), map()) ::
          Ecto.Changeset.t()
  def change_policy_assignment(%Person{} = person, attrs) do
    PersonPolicyAssignment.changeset(%PersonPolicyAssignment{person_id: person.id}, attrs)
  end

  def change_policy_assignment(%PersonPolicyAssignment{} = assignment, attrs) do
    PersonPolicyAssignment.changeset(assignment, attrs)
  end

  @doc "The changeset a calendar assignment's form binds to."
  @spec change_calendar_assignment(Person.t() | PersonCalendar.t(), map()) :: Ecto.Changeset.t()
  def change_calendar_assignment(%Person{} = person, attrs) do
    PersonCalendar.changeset(%PersonCalendar{person_id: person.id}, attrs)
  end

  def change_calendar_assignment(%PersonCalendar{} = assignment, attrs) do
    PersonCalendar.changeset(assignment, attrs)
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
  def fetch_person(id), do: Repo.fetch(Person, id)

  @doc "The person's manager, or `:error` where they have none."
  @spec fetch_manager(Person.t()) :: {:ok, Person.t()} | :error
  def fetch_manager(%{manager_id: nil}), do: :error
  def fetch_manager(person), do: fetch_person(person.manager_id)

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

  @doc "Puts a person on a calendar from a date."
  @spec create_calendar_assignment(Person.t(), Person.t() | nil, map()) ::
          Audit.written(PersonCalendar.t())
  def create_calendar_assignment(person, actor, attrs) do
    %PersonCalendar{person_id: person.id}
    |> PersonCalendar.changeset(attrs)
    |> Audit.write("calendar_assignment.created", actor, person.id)
  end

  @doc "Corrects which calendar a person was on, or from when."
  @spec update_calendar_assignment(PersonCalendar.t(), Person.t() | nil, map()) ::
          Audit.written(PersonCalendar.t())
  def update_calendar_assignment(assignment, actor, attrs) do
    assignment
    |> PersonCalendar.changeset(attrs)
    |> Audit.write("calendar_assignment.updated", actor, assignment.person_id)
  end

  @doc "Removes a calendar assignment, letting whatever preceded it run on."
  @spec delete_calendar_assignment(PersonCalendar.t(), Person.t() | nil) ::
          Audit.written(PersonCalendar.t())
  def delete_calendar_assignment(assignment, actor) do
    Audit.delete(assignment, "calendar_assignment.deleted", actor, assignment.person_id)
  end

  @doc """
  The work pattern a person is on `date`.

  `:error` before their first pattern takes effect.
  """
  @spec fetch_work_pattern_on(Person.t(), Date.t()) :: {:ok, WorkPattern.t()} | :error
  def fetch_work_pattern_on(person, date) do
    person |> succession(WorkPattern) |> Timeline.fetch(date)
  end

  @doc "One of the person's work patterns, or `:error` where it is not theirs."
  @spec fetch_work_pattern(Person.t(), Ecto.UUID.t()) :: {:ok, WorkPattern.t()} | :error
  def fetch_work_pattern(person, id), do: fetch_of(WorkPattern, person, id)

  @doc "One of the person's policy assignments, or `:error` where it is not theirs."
  @spec fetch_policy_assignment(Person.t(), Ecto.UUID.t()) ::
          {:ok, PersonPolicyAssignment.t()} | :error
  def fetch_policy_assignment(person, id), do: fetch_of(PersonPolicyAssignment, person, id)

  @doc "One of the person's calendar assignments, or `:error` where it is not theirs."
  @spec fetch_calendar_assignment(Person.t(), Ecto.UUID.t()) :: {:ok, PersonCalendar.t()} | :error
  def fetch_calendar_assignment(person, id), do: fetch_of(PersonCalendar, person, id)

  @doc "Every work pattern a person has been on, earliest first."
  @spec work_patterns(Person.t()) :: [WorkPattern.t()]
  def work_patterns(person), do: Repo.all(effective_dated(WorkPattern, person))

  @doc "Every policy a person has been on, earliest first, each with the policy."
  @spec policy_assignments(Person.t()) :: [PersonPolicyAssignment.t()]
  def policy_assignments(person) do
    Repo.all(preload(effective_dated(PersonPolicyAssignment, person), :leave_policy))
  end

  @doc "Every calendar a person has been on, earliest first, each with the calendar and country."
  @spec calendar_assignments(Person.t()) :: [PersonCalendar.t()]
  def calendar_assignments(person) do
    Repo.all(preload(effective_dated(PersonCalendar, person), calendar: :parent))
  end

  @doc """
  Whether anybody reports to `person`.

  Being a manager is not a role but a consequence, so this is the question asked of somebody
  wherever a manager's standing decides something. Whoever has left is still counted: their
  requests outlive their leaving, and `Leaf.Leave.awaiting/1` will hand them over all the same.
  """
  @spec manager?(Person.t()) :: boolean()
  def manager?(person) do
    Repo.exists?(from other in Person, where: other.manager_id == ^person.id)
  end

  @doc """
  Whether `actor` may see and act on `person`'s record.

  Yourself, anyone who reports to you, and anyone at all if you administer the organisation. This
  is §5.9's privacy line: leave detail is the person's, their manager's and payroll's business.
  """
  @spec oversees?(Person.t(), Person.t()) :: boolean()
  def oversees?(actor, person) do
    actor.id == person.id or person.manager_id == actor.id or actor.role == :admin
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
  The hours the person works on each date in `range` they are on a pattern for, in order.

  A date before their first pattern takes effect is left out rather than given none: nobody knows
  what they worked, which is not the same as their having worked nothing.
  """
  @spec hours_per_day(Person.t(), Date.Range.t()) :: [{Date.t(), Decimal.t()}]
  def hours_per_day(person, range) do
    person |> work_pattern_segments(range) |> hours_worked()
  end

  @doc """
  The same, refusing a `range` the person has no pattern over part of.

  Anything working out entitlement wants this rather than a partial answer, for the reason
  `work_pattern_segments!/2` gives.
  """
  @spec hours_per_day!(Person.t(), Date.Range.t()) :: [{Date.t(), Decimal.t()}]
  def hours_per_day!(person, range) do
    person |> work_pattern_segments!(range) |> hours_worked()
  end

  @doc "The id of the leave policy the person is on over each part of `range`."
  @spec leave_policy_segments(Person.t(), Date.Range.t()) :: [segment(Ecto.UUID.t())]
  def leave_policy_segments(person, range) do
    person
    |> succession(PersonPolicyAssignment)
    |> Timeline.segments(range)
    |> Enum.map(fn {span, assignment} -> {span, assignment.leave_policy_id} end)
  end

  @doc """
  Everyone who has ever been put on that leave policy, by name.

  Whoever has been on it at some point, not who is on it now: what a policy granted somebody is
  still theirs after they move off it.
  """
  @spec on_policy(Ecto.UUID.t()) :: [Person.t()]
  def on_policy(leave_policy_id) do
    Repo.all(
      from person in Person,
        join: assignment in PersonPolicyAssignment,
        on: assignment.person_id == person.id,
        where: assignment.leave_policy_id == ^leave_policy_id,
        distinct: true,
        order_by: person.name
    )
  end

  @doc "Everyone in an organisation, by name."
  @spec people(Ecto.UUID.t()) :: [Person.t()]
  def people(organisation_id) do
    Repo.all(
      from person in Person,
        where: person.organisation_id == ^organisation_id,
        order_by: person.name
    )
  end

  @doc """
  The public holidays a person observes over `range`, in date order.

  Which calendar they are on can change within the range, so each stretch is read against the
  calendar in force over it, its country's holidays included. A stretch they are on no calendar for
  contributes nothing, because a calendar nobody has assigned holds no holidays to show.
  """
  @spec public_holidays(Person.t(), Date.Range.t()) :: [PublicHoliday.t()]
  def public_holidays(person, range) do
    person |> calendar_segments(range) |> observed()
  end

  @doc """
  The same, refusing a `range` the person is on no calendar over part of.

  Anything counting a person's whole share of the calendar wants this rather than a partial answer:
  a stretch nobody has said where they are is a hole in the record, and counted as none it would
  quietly leave them short.
  """
  @spec public_holidays!(Person.t(), Date.Range.t()) :: [PublicHoliday.t()]
  def public_holidays!(person, range) do
    person |> calendar_segments(range) |> covering!(range, person, "calendar") |> observed()
  end

  @doc """
  The date it is where the person is.

  Every page showing a date shows it to somebody, and it is their day it is meant to be (§4.11).
  """
  @spec today(Person.t()) :: Date.t()
  def today(person), do: person |> time_zone() |> DateTime.now!() |> DateTime.to_date()

  @doc """
  The time zone of the calendar the person is on, or UTC where they are on none.

  Where somebody is is a question about now, so it is the calendar in force today that answers it
  rather than the one in force on whatever date is being displayed.
  """
  @spec time_zone(Person.t()) :: String.t()
  def time_zone(person) do
    person |> succession(PersonCalendar, :calendar) |> Timeline.fetch(Date.utc_today()) |> zone()
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

  defp fetch_of(schema, person, id), do: Repo.fetch(schema, id, person_id: person.id)

  defp effective_dated(schema, person) do
    from row in schema, where: row.person_id == ^person.id, order_by: row.effective_from
  end

  defp succession(person, schema, preloads \\ []) do
    Repo.all(from row in schema, where: row.person_id == ^person.id, preload: ^preloads)
  end

  defp calendar_segments(person, range) do
    person
    |> succession(PersonCalendar)
    |> Timeline.segments(range)
    |> Enum.map(fn {span, assignment} -> {span, assignment.calendar_id} end)
  end

  defp observed(segments) do
    Enum.flat_map(segments, fn {span, calendar_id} -> Org.observed_holidays(calendar_id, span) end)
  end

  defp zone({:ok, assignment}), do: assignment.calendar.time_zone
  defp zone(:error), do: "Etc/UTC"

  defp hours_worked(segments) do
    Enum.flat_map(segments, fn {span, pattern} -> Enum.map(span, &{&1, hours_on(pattern, &1)}) end)
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
