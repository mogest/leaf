defmodule Leaf.Reports do
  @moduledoc """
  The reports an administrator reads the organisation off and hands payroll (§5.6), each a table.

  Nothing is kept: a report is worked out from the leave each time it is asked for, so it is never
  behind it. What it is asked for — which report, over which dates —
  comes in as params, defaulted from the reader's own today.
  """

  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.Reports.Options
  alias Leaf.Reports.Payroll
  alias Leaf.Reports.Table

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

  @doc "A report as CSV."
  @spec csv(Table.t()) :: String.t()
  defdelegate csv(table), to: Table

  defp table(:ipayroll, person, options) do
    Payroll.table(person.organisation_id, Options.period(options))
  end
end
