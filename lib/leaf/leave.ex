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
  alias Leaf.Leave.Request
  alias Leaf.Leave.WorkingDay
  alias Leaf.People.Person
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
  Every day of approved leave a person has taken up to and including `date`, oldest first.

  Leave dated before the organisation started tracking still counts, so this has no floor: it
  draws down the opening balance that accounts for that period.
  """
  @spec days_taken(Person.t(), Date.t()) :: [Day.t()]
  def days_taken(person, date) do
    Repo.all(
      from day in Day,
        join: request in assoc(day, :leave_request),
        where: request.person_id == ^person.id and request.status == :approved,
        where: day.date <= ^date,
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
        preload: [:days, :reviewed_by]
    )
  end

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

  @doc "Every balance figure entered for a person up to and including `date`, oldest first."
  @spec balance_entries(Person.t(), Date.t()) :: [BalanceEntry.t()]
  def balance_entries(person, date) do
    Repo.all(
      from entry in BalanceEntry,
        where: entry.person_id == ^person.id and entry.date <= ^date,
        order_by: entry.date
    )
  end

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

  defp revisable?(%{status: :pending} = request, actor) do
    actor.id in [request.person_id, request.submitted_by_id] or approver?(request.person, actor)
  end

  defp revisable?(%{status: :approved} = request, actor), do: approver?(request.person, actor)
  defp revisable?(_request, _actor), do: false

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
