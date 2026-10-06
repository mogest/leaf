defmodule Leaf.Reports do
  @moduledoc """
  The reports an administrator reads the organisation off and hands payroll (§5.6), each a table.

  Nothing is kept: a report is worked out from the leave, the ledger and the audit log each time it
  is asked for, so it is never behind them. What it is asked for — which report, over which dates —
  comes in as params, defaulted from the reader's own today, and the times it shows are theirs.
  """

  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.Reports.Balances
  alias Leaf.Reports.Expiring
  alias Leaf.Reports.Options
  alias Leaf.Reports.Payroll
  alias Leaf.Reports.Reconciliation
  alias Leaf.Reports.Table
  alias Leaf.Reports.Taken

  @doc "The changeset a report's options form binds to, its blanks filled from `person`'s today."
  @spec change_options(Person.t(), map()) :: Ecto.Changeset.t()
  def change_options(person, params), do: Options.changeset(People.today(person), params)

  @doc """
  The report `params` ask for, over `person`'s organisation.

  `params` name the report under `report` and what it is over in the rest, as `change_options/2`
  takes them.
  """
  @spec run(Person.t(), map()) :: {:ok, Table.t()} | {:error, Ecto.Changeset.t()}
  def run(person, params) do
    with {:ok, options} <- Ecto.Changeset.apply_action(change_options(person, params), :run) do
      {:ok, table(options.report, person, options)}
    end
  end

  @doc "A report as CSV, its moments said in `zone`."
  @spec csv(Table.t(), String.t()) :: String.t()
  defdelegate csv(table, zone), to: Table

  defp table(:ipayroll, person, options) do
    Payroll.table(person.organisation_id, Options.period(options))
  end

  defp table(:taken, person, options) do
    Taken.table(
      person.organisation_id,
      Options.period(options),
      options.country_id,
      options.leave_type_id
    )
  end

  defp table(:reconciliation, person, options) do
    Reconciliation.table(
      person.organisation_id,
      Options.period(options),
      options.cut_off,
      People.time_zone(person)
    )
  end

  defp table(:balances, person, options) do
    Balances.table(person.organisation_id, options.as_at)
  end

  defp table(:expiring, person, options) do
    Expiring.table(person.organisation_id, options.as_at, options.within)
  end
end
