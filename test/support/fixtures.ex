defmodule Leaf.Fixtures do
  @moduledoc "Minimal persisted records for tests, built through the schemas' own changesets."

  alias Leaf.Org.Organisation
  alias Leaf.People.Person
  alias Leaf.Policies.LeavePolicy
  alias Leaf.Policies.LeaveType
  alias Leaf.Repo

  @spec organisation(map()) :: Organisation.t()
  def organisation(attrs \\ %{}) do
    insert(%Organisation{}, &Organisation.changeset/2, attrs, %{
      name: "Fernbank Collective",
      full_time_week_hours: "40",
      standard_day_hours: "8",
      year_start_month: 1
    })
  end

  @spec person(map()) :: Person.t()
  def person(attrs \\ %{}) do
    insert(%Person{}, &Person.changeset/2, attrs, %{
      name: "Rae Halloran",
      email: "rae#{System.unique_integer([:positive])}@example.test",
      role: :member,
      employment_start_date: ~D[2024-03-04]
    })
  end

  @spec leave_type(map()) :: LeaveType.t()
  def leave_type(attrs \\ %{}) do
    insert(%LeaveType{}, &LeaveType.changeset/2, attrs, %{
      name: "Annual leave",
      unit: :hours,
      position: 1
    })
  end

  @spec leave_policy(map()) :: LeavePolicy.t()
  def leave_policy(attrs \\ %{}) do
    insert(%LeavePolicy{}, &LeavePolicy.changeset/2, attrs, %{name: "Standard employee"})
  end

  defp insert(struct, changeset, attrs, defaults) do
    struct |> changeset.(Map.merge(defaults, attrs)) |> Repo.insert!()
  end
end
