defmodule Leaf.Leave do
  @moduledoc """
  Leave taken, and the balance figures entered by hand.

  What a person is entitled to is not here — it follows from their dates, hours and policy, and
  `Leaf.Ledger` works it out. This holds the two things that cannot be worked out: the leave
  somebody filed, and the opening balances and adjustments an administrator entered.
  """

  import Ecto.Query

  alias Leaf.Leave.BalanceEntry
  alias Leaf.Leave.Day
  alias Leaf.People.Person
  alias Leaf.Repo

  @doc "Records an opening balance or an adjustment."
  @spec create_balance_entry(map()) :: {:ok, BalanceEntry.t()} | {:error, Ecto.Changeset.t()}
  def create_balance_entry(attrs) do
    %BalanceEntry{} |> BalanceEntry.changeset(attrs) |> Repo.insert()
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

  @doc "Every balance figure entered for a person up to and including `date`, oldest first."
  @spec balance_entries(Person.t(), Date.t()) :: [BalanceEntry.t()]
  def balance_entries(person, date) do
    Repo.all(
      from entry in BalanceEntry,
        where: entry.person_id == ^person.id and entry.date <= ^date,
        order_by: entry.date
    )
  end
end
