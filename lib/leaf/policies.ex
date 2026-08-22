defmodule Leaf.Policies do
  @moduledoc """
  Leave types, and the policies that say what each of them grants.

  A policy is about nobody in particular, so its audit entries name no subject even though a
  change here moves the entitlement of everybody on it. Withdrawing a leave type or a policy is
  archiving rather than deleting, since what they granted has to keep making sense; an entitlement
  is closed by giving it an end date, and deleted only where it should never have existed.
  """

  import Ecto.Query

  alias Leaf.Audit
  alias Leaf.Org.Organisation
  alias Leaf.People.Person
  alias Leaf.Policies.LeavePolicy
  alias Leaf.Policies.LeaveType
  alias Leaf.Policies.PolicyEntitlement
  alias Leaf.Repo

  @doc "Creates a leave type."
  @spec create_leave_type(Organisation.t(), Person.t() | nil, map()) ::
          Audit.written(LeaveType.t())
  def create_leave_type(organisation, actor, attrs) do
    %LeaveType{organisation_id: organisation.id}
    |> LeaveType.changeset(attrs)
    |> Audit.write("leave_type.created", actor)
  end

  @doc "The changeset a leave type's form binds to."
  @spec change_leave_type(Organisation.t() | LeaveType.t(), map()) :: Ecto.Changeset.t()
  def change_leave_type(%Organisation{} = organisation, attrs) do
    LeaveType.changeset(%LeaveType{organisation_id: organisation.id}, attrs)
  end

  def change_leave_type(%LeaveType{} = leave_type, attrs),
    do: LeaveType.changeset(leave_type, attrs)

  @doc "The changeset a leave policy's form binds to."
  @spec change_leave_policy(Organisation.t() | LeavePolicy.t(), map()) :: Ecto.Changeset.t()
  def change_leave_policy(%Organisation{} = organisation, attrs) do
    LeavePolicy.changeset(%LeavePolicy{organisation_id: organisation.id}, attrs)
  end

  def change_leave_policy(%LeavePolicy{} = policy, attrs),
    do: LeavePolicy.changeset(policy, attrs)

  @doc "The changeset a new entitlement's form binds to."
  @spec change_entitlement(LeavePolicy.t(), LeaveType.t() | nil, map()) :: Ecto.Changeset.t()
  def change_entitlement(policy, leave_type, attrs) do
    PolicyEntitlement.changeset(
      %PolicyEntitlement{leave_policy_id: policy.id, leave_type_id: leave_type && leave_type.id},
      attrs
    )
  end

  @doc "The changeset an existing entitlement's form binds to."
  @spec change_entitlement(PolicyEntitlement.t(), map()) :: Ecto.Changeset.t()
  def change_entitlement(entitlement, attrs), do: PolicyEntitlement.changeset(entitlement, attrs)

  @doc "Amends a leave type, which is also how one is archived."
  @spec update_leave_type(LeaveType.t(), Person.t() | nil, map()) :: Audit.written(LeaveType.t())
  def update_leave_type(leave_type, actor, attrs) do
    leave_type |> LeaveType.changeset(attrs) |> Audit.write("leave_type.updated", actor)
  end

  @doc "Creates a leave policy."
  @spec create_leave_policy(Organisation.t(), Person.t() | nil, map()) ::
          Audit.written(LeavePolicy.t())
  def create_leave_policy(organisation, actor, attrs) do
    %LeavePolicy{organisation_id: organisation.id}
    |> LeavePolicy.changeset(attrs)
    |> Audit.write("leave_policy.created", actor)
  end

  @doc "Amends a leave policy, which is also how one is archived."
  @spec update_leave_policy(LeavePolicy.t(), Person.t() | nil, map()) ::
          Audit.written(LeavePolicy.t())
  def update_leave_policy(policy, actor, attrs) do
    policy |> LeavePolicy.changeset(attrs) |> Audit.write("leave_policy.updated", actor)
  end

  @doc "Creates one of a policy's entitlements, for one leave type."
  @spec create_entitlement(LeavePolicy.t(), LeaveType.t(), Person.t() | nil, map()) ::
          Audit.written(PolicyEntitlement.t())
  def create_entitlement(policy, leave_type, actor, attrs) do
    %PolicyEntitlement{leave_policy_id: policy.id, leave_type_id: leave_type.id}
    |> PolicyEntitlement.changeset(attrs)
    |> Audit.write("policy_entitlement.created", actor)
  end

  @doc """
  Amends an entitlement.

  Closing one means setting `effective_to`, and succeeding it means closing it before the next
  begins: two entitlements for one leave type under one policy may not overlap.
  """
  @spec update_entitlement(PolicyEntitlement.t(), Person.t() | nil, map()) ::
          Audit.written(PolicyEntitlement.t())
  def update_entitlement(entitlement, actor, attrs) do
    entitlement
    |> PolicyEntitlement.changeset(attrs)
    |> Audit.write("policy_entitlement.updated", actor)
  end

  @doc """
  Removes an entitlement outright.

  For one that should never have existed. An entitlement that ran and is now over is closed with
  `effective_to` instead, so what it granted still has something to account for it.
  """
  @spec delete_entitlement(PolicyEntitlement.t(), Person.t() | nil) ::
          Audit.written(PolicyEntitlement.t())
  def delete_entitlement(entitlement, actor) do
    Audit.delete(entitlement, "policy_entitlement.deleted", actor)
  end

  @doc "Every leave type the organisation offers, archived ones included, in its own order."
  @spec leave_types(Ecto.UUID.t()) :: [LeaveType.t()]
  def leave_types(organisation_id) do
    Repo.all(
      from type in LeaveType,
        where: type.organisation_id == ^organisation_id,
        order_by: type.position
    )
  end

  @doc "Every leave policy the organisation offers, archived ones included, by name."
  @spec leave_policies(Ecto.UUID.t()) :: [LeavePolicy.t()]
  def leave_policies(organisation_id) do
    Repo.all(
      from policy in LeavePolicy,
        where: policy.organisation_id == ^organisation_id,
        order_by: policy.name
    )
  end

  @doc "The leave type, or `:error` where no such type exists."
  @spec fetch_leave_type(Ecto.UUID.t()) :: {:ok, LeaveType.t()} | :error
  def fetch_leave_type(id), do: fetched(Repo.get(LeaveType, id))

  @doc "The leave policy, or `:error` where no such policy exists."
  @spec fetch_leave_policy(Ecto.UUID.t()) :: {:ok, LeavePolicy.t()} | :error
  def fetch_leave_policy(id), do: fetched(Repo.get(LeavePolicy, id))

  @doc "The entitlement with its leave type, or `:error` where no such entitlement exists."
  @spec fetch_entitlement(Ecto.UUID.t()) :: {:ok, PolicyEntitlement.t()} | :error
  def fetch_entitlement(id) do
    case Repo.get(PolicyEntitlement, id) do
      nil -> :error
      entitlement -> {:ok, Repo.preload(entitlement, :leave_type)}
    end
  end

  @doc """
  Every entitlement a policy has ever held, with its leave type.

  One leave type's entitlements arrive together and in the order they take effect, so a type's
  whole succession — including the windows it was not offered over — can be read off the list.
  """
  @spec entitlements(Ecto.UUID.t()) :: [PolicyEntitlement.t()]
  def entitlements(leave_policy_id), do: Repo.all(of_policy(leave_policy_id))

  @doc """
  Every entitlement of a policy whose life overlaps `range`, with its leave type.

  One leave type's entitlements arrive together and in the order they take effect, so a type's
  succession can be read straight off the list.
  """
  @spec entitlements(Ecto.UUID.t(), Date.Range.t()) :: [PolicyEntitlement.t()]
  def entitlements(leave_policy_id, range) do
    Repo.all(
      from entitlement in of_policy(leave_policy_id),
        where: entitlement.effective_from <= ^range.last,
        where: is_nil(entitlement.effective_to) or entitlement.effective_to >= ^range.first
    )
  end

  defp of_policy(leave_policy_id) do
    from entitlement in PolicyEntitlement,
      join: leave_type in assoc(entitlement, :leave_type),
      where: entitlement.leave_policy_id == ^leave_policy_id,
      order_by: [leave_type.position, entitlement.leave_type_id, entitlement.effective_from],
      preload: [leave_type: leave_type]
  end

  defp fetched(nil), do: :error
  defp fetched(record), do: {:ok, record}
end
