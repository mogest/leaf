defmodule Leaf.Leave do
  @moduledoc """
  Leave taken, and the balance figures entered by hand.

  What a person is entitled to is not here — it follows from their dates, hours and policy, and
  `Leaf.Ledger` works it out. This holds the two things that cannot be worked out: the leave
  somebody filed, and the opening balances and adjustments an administrator entered.

  Every write takes whoever is acting, because who may do what turns on them. While a request is
  pending the person it belongs to may revise it; once it is approved only their manager or an
  administrator may, so that nobody can quietly remove leave they have already taken. Where a
  person has no manager, an administrator stands in. A refusal comes back as `{:error, :forbidden}`
  rather than a changeset — nothing about it is a matter of what was filled in — and a write that
  goes through records itself in the audit log.
  """

  import Ecto.Query

  alias Leaf.Audit
  alias Leaf.Dates
  alias Leaf.Leave.BalanceEntry
  alias Leaf.Leave.Day
  alias Leaf.Leave.Diary
  alias Leaf.Leave.Month
  alias Leaf.Leave.Request
  alias Leaf.Leave.WorkingDay
  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.Policies
  alias Leaf.Policies.LeaveType
  alias Leaf.Repo

  @typedoc """
  One line of a request: an amount of one leave type on one date, in whichever unit was asked for.

  A whole day is `%{unit: :days, amount: 1}` whatever unit the leave type counts in, and stays a
  whole day if the person's hours change before the date.
  """
  @type entry :: %{
          leave_type_id: Ecto.UUID.t(),
          date: Date.t(),
          amount: Decimal.t() | binary() | integer(),
          unit: Day.unit()
        }

  @doc "The request, with its person and days, or `:error` where no such request exists."
  @spec fetch_request(Ecto.UUID.t()) :: {:ok, Request.t()} | :error
  def fetch_request(id) do
    case Repo.get(Request, id) do
      nil -> :error
      request -> {:ok, Repo.preload(request, [:days, :person])}
    end
  end

  @doc """
  Files a request for `person`, pending a decision.

  `attrs` carries a `:days` list of `t:entry/0` and an optional `:note`.
  """
  @spec request(Person.t(), Person.t(), map()) ::
          {:ok, Request.t()} | {:error, Ecto.Changeset.t() | :forbidden}
  def request(person, actor, attrs) do
    with :ok <- permit(person.id == actor.id or approver?(person, actor)) do
      %Request{person_id: person.id, submitted_by_id: actor.id, status: :pending}
      |> Request.changeset(measured(person, attrs))
      |> Audit.write("leave_request.requested", actor, person.id)
    end
  end

  @doc """
  Replaces what a request asks for, leaving its status alone.

  The days given are the whole of it, so amending is how a request is shortened as well as changed.
  """
  @spec amend(Request.t(), Person.t(), map()) ::
          {:ok, Request.t()} | {:error, Ecto.Changeset.t() | :forbidden}
  def amend(request, actor, attrs) do
    with :ok <- permit(revisable?(request, actor)) do
      request
      |> Request.changeset(measured(request.person, attrs))
      |> Audit.write("leave_request.amended", actor, request.person_id)
    end
  end

  @doc "Approves a pending request."
  @spec approve(Request.t(), Person.t(), String.t() | nil) ::
          {:ok, Request.t()} | {:error, Ecto.Changeset.t() | :forbidden}
  def approve(request, actor, comment \\ nil), do: decide(request, actor, :approved, comment)

  @doc "Declines a pending request."
  @spec decline(Request.t(), Person.t(), String.t() | nil) ::
          {:ok, Request.t()} | {:error, Ecto.Changeset.t() | :forbidden}
  def decline(request, actor, comment \\ nil), do: decide(request, actor, :declined, comment)

  @doc """
  Cancels a request, returning what it drew.

  Cancelling is a decision, so a cancelled request records who cancelled it rather than who
  approved it. The approval it replaced is in the audit log.
  """
  @spec cancel(Request.t(), Person.t()) ::
          {:ok, Request.t()} | {:error, Ecto.Changeset.t() | :forbidden}
  def cancel(request, actor) do
    with :ok <- permit(revisable?(request, actor)) do
      review(request, actor, :cancelled, nil)
    end
  end

  @doc """
  Records an opening balance or an adjustment, which only an administrator may do.

  An adjustment needs a reason; an opening balance is its own explanation.
  """
  @spec create_balance_entry(Person.t(), Person.t(), map()) ::
          {:ok, BalanceEntry.t()} | {:error, Ecto.Changeset.t() | :forbidden}
  def create_balance_entry(person, actor, attrs) do
    with :ok <- permit(actor.role == :admin) do
      %BalanceEntry{person_id: person.id, created_by_id: actor.id}
      |> BalanceEntry.changeset(attrs)
      |> Audit.write("balance_entry.created", actor, person.id)
    end
  end

  @doc "The changeset a balance entry's form binds to."
  @spec change_balance_entry(Person.t(), map()) :: Ecto.Changeset.t()
  def change_balance_entry(person, attrs) do
    BalanceEntry.changeset(%BalanceEntry{person_id: person.id}, attrs)
  end

  @doc """
  Each day in `range` the person works, with the hours they work on it.

  A multi-day request covers these and nothing else: neither a day off their pattern nor a public
  holiday their policy grants them off is leave, and a date they are on no pattern for is a hole in
  the record rather than a day anybody may book.
  """
  @spec working_days(Person.t(), Date.Range.t()) :: [{Date.t(), Decimal.t()}]
  def working_days(person, range) do
    person |> WorkingDay.hours_per_day(range) |> Enum.filter(&Decimal.positive?(elem(&1, 1)))
  end

  @doc """
  Every day of approved leave a person holds, oldest first.

  Bounded at neither end. Leave somebody is already going on is spent whether they have been on it
  yet or not, and leave dated before the organisation started tracking draws down the opening
  balance that accounts for that period.
  """
  @spec days_approved(Person.t()) :: [Day.t()]
  def days_approved(person) do
    Repo.all(
      from day in Day,
        join: request in assoc(day, :leave_request),
        where: request.person_id == ^person.id and request.status == :approved,
        order_by: day.date
    )
  end

  @doc """
  Every day of leave a person has asked for and nobody has decided yet, oldest first.

  Undecided leave is mostly ahead of the person, so this has no ceiling: what they are waiting on
  is waiting whatever date it falls on.
  """
  @spec days_awaiting(Person.t()) :: [Day.t()]
  def days_awaiting(person) do
    Repo.all(
      from day in Day,
        join: request in assoc(day, :leave_request),
        where: request.person_id == ^person.id and request.status == :pending,
        order_by: day.date
    )
  end

  @doc """
  A person's requests, the leave furthest ahead first, each with its days and whoever decided it.

  A request holds no date of its own, so they are ordered by the first day each one covers. All of
  them: how many to show, and how many are left over, is the page's to decide.
  """
  @spec requests(Person.t()) :: [Request.t()]
  def requests(person) do
    Repo.all(
      from request in Request,
        left_join: day in assoc(request, :days),
        where: request.person_id == ^person.id,
        group_by: request.id,
        order_by: [desc: min(day.date)],
        preload: [:person, :reviewed_by, days: :leave_type]
    )
  end

  @doc """
  The months `range` runs over, as the weeks they are made of, marked with the person's own days.

  Leave they still hold, the public holidays they observe and the days they do not work all read
  off the same dates, so anything showing months needs nothing else to draw them.
  """
  @spec calendar(Person.t(), Date.Range.t()) :: [Month.t()]
  def calendar(person, range), do: Month.over(person, range, days_filed(person, range))

  @doc """
  Each of `people` and their own dates across `range`, as `viewer` may see them.

  The same days a calendar is drawn from, laid out as a row each rather than as months. Leave
  nobody has decided on yet is the person's own business, so it reaches only whoever their record
  is open to under §5.9; to everybody else the day is one they are not away on.
  """
  @spec away([Person.t()], Person.t(), Date.Range.t()) :: [{Person.t(), [Diary.day()]}]
  def away(people, viewer, range) do
    Enum.map(people, &{&1, Diary.over(&1, range, seen(&1, viewer, range))})
  end

  defp seen(person, viewer, range) do
    days = days_filed(person, range)

    case People.oversees?(viewer, person) do
      true -> days
      false -> Enum.reject(days, &(&1.leave_request.status == :pending))
    end
  end

  @doc """
  The pending requests `approver` is the one to decide, the leave furthest ahead first.

  An administrator decides for the whole organisation, which is §5.3's fallback for a person whose
  manager is not there to do it; anybody else decides for the people who report to them.
  """
  @spec awaiting(Person.t()) :: [Request.t()]
  def awaiting(approver) do
    Repo.all(
      from request in Request,
        join: person in assoc(request, :person),
        left_join: day in assoc(request, :days),
        where: request.status == :pending,
        where: ^overseen(approver),
        group_by: request.id,
        order_by: [desc: min(day.date)],
        preload: [:person, days: :leave_type]
    )
  end

  @doc """
  The leave types a person may file against over `range`, in the organisation's order.

  What somebody may ask for comes from the policy they are on, not from what they hold a balance
  in: a type that grants nothing and is only recorded is still one they may file.
  """
  @spec requestable(Person.t(), Date.Range.t()) :: [LeaveType.t()]
  def requestable(person, range) do
    person
    |> People.leave_policy_segments(range)
    |> Enum.flat_map(fn {span, policy_id} -> Policies.entitlements(policy_id, span) end)
    |> Enum.map(& &1.leave_type)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.position)
  end

  @doc """
  The days `entries` describe, as days, without filing them.

  What a balance would be were a request approved is `Leaf.Ledger.statements/3` given these, so
  this is how a form asks the question before there is anything to ask it about.
  """
  @spec proposed([entry()]) :: [Day.t()]
  def proposed(entries), do: Enum.map(entries, &struct!(Day, &1))

  @doc """
  Every day of leave a person still holds within `range`, oldest first, with its request.

  Approved and pending only. A declined day was never leave and a cancelled one has stopped being
  it, so neither belongs on a calendar; a pending one does, because the person is counting on it.
  """
  @spec days_filed(Person.t(), Date.Range.t()) :: [Day.t()]
  def days_filed(person, range) do
    Repo.all(
      from day in Day,
        join: request in assoc(day, :leave_request),
        where: request.person_id == ^person.id,
        where: request.status in [:approved, :pending],
        where: day.date >= ^range.first and day.date <= ^range.last,
        order_by: day.date,
        preload: [leave_request: request]
    )
  end

  @doc """
  Whether `actor` may amend or cancel `request` as it stands.

  Its person must be loaded. This is the rule §5.4 states, asked rather than repeated: a page
  showing an amend or a cancel asks here whether to show it, and the write checks it again.
  """
  @spec revisable?(Request.t(), Person.t()) :: boolean()
  def revisable?(%{status: :pending} = request, actor) do
    actor.id in [request.person_id, request.submitted_by_id] or approver?(request.person, actor)
  end

  def revisable?(%{status: :approved} = request, actor), do: approver?(request.person, actor)
  def revisable?(_request, _actor), do: false

  @doc "Every balance figure entered for a person, oldest first, whatever it is dated."
  @spec balance_entries(Person.t()) :: [BalanceEntry.t()]
  def balance_entries(person), do: Repo.all(entered(person))

  @doc "Every balance figure entered for a person up to and including `date`, oldest first."
  @spec balance_entries(Person.t(), Date.t()) :: [BalanceEntry.t()]
  def balance_entries(person, date) do
    Repo.all(from entry in entered(person), where: entry.date <= ^date)
  end

  defp entered(person) do
    from entry in BalanceEntry, where: entry.person_id == ^person.id, order_by: entry.date
  end

  defp overseen(%{role: :admin} = approver) do
    dynamic([_request, person], person.organisation_id == ^approver.organisation_id)
  end

  defp overseen(approver), do: dynamic([_request, person], person.manager_id == ^approver.id)

  defp decide(request, actor, status, comment) do
    with :ok <- permit(request.status == :pending and approver?(request.person, actor)) do
      review(request, actor, status, comment)
    end
  end

  defp review(request, actor, status, comment) do
    request
    |> Request.review_changeset(%{
      status: status,
      reviewed_by_id: actor.id,
      reviewed_at: DateTime.truncate(DateTime.utc_now(), :second),
      review_comment: comment
    })
    |> Audit.write("leave_request.#{status}", actor, request.person_id)
  end

  defp approver?(person, actor), do: person.manager_id == actor.id or actor.role == :admin

  defp permit(true), do: :ok
  defp permit(false), do: {:error, :forbidden}

  # The hours are the day's own check that it falls on one the person works, and are not kept:
  # what a day is worth follows from the pattern in force when it comes round, not when it is
  # asked for. A date with no pattern behind it has none to give, and the day refuses itself.
  defp measured(person, %{days: [_first | _rest] = entries} = attrs) do
    hours = person |> WorkingDay.hours_per_day(spanned(entries)) |> Map.new()

    %{attrs | days: Enum.map(entries, &Map.put(&1, :hours_in_day, hours[&1.date]))}
  end

  defp measured(_person, attrs), do: attrs

  defp spanned(entries), do: entries |> Enum.map(& &1.date) |> Dates.spanning()
end
