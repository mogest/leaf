defmodule Leaf.Policies do
  @moduledoc "Leave types, and the policies that say what each of them grants."

  import Ecto.Query

  alias Leaf.Policies.LeavePolicy
  alias Leaf.Policies.LeaveType
  alias Leaf.Policies.PolicyEntitlement
  alias Leaf.Repo

  @doc "Creates a leave type."
  @spec create_leave_type(map()) :: {:ok, LeaveType.t()} | {:error, Ecto.Changeset.t()}
  def create_leave_type(attrs), do: %LeaveType{} |> LeaveType.changeset(attrs) |> Repo.insert()

  @doc "Creates a leave policy."
  @spec create_leave_policy(map()) :: {:ok, LeavePolicy.t()} | {:error, Ecto.Changeset.t()}
  def create_leave_policy(attrs) do
    %LeavePolicy{} |> LeavePolicy.changeset(attrs) |> Repo.insert()
  end

  @doc "Creates one of a policy's entitlements."
  @spec create_entitlement(map()) :: {:ok, PolicyEntitlement.t()} | {:error, Ecto.Changeset.t()}
  def create_entitlement(attrs) do
    %PolicyEntitlement{} |> PolicyEntitlement.changeset(attrs) |> Repo.insert()
  end

  @doc """
  Every entitlement of a policy whose life overlaps `range`, with its leave type.

  Grouped by leave type and ordered within a type by when each takes effect, so one type's
  entitlements arrive as the succession they are.
  """
  @spec entitlements(Ecto.UUID.t(), Date.Range.t()) :: [PolicyEntitlement.t()]
  def entitlements(leave_policy_id, range) do
    Repo.all(
      from entitlement in PolicyEntitlement,
        join: leave_type in assoc(entitlement, :leave_type),
        where: entitlement.leave_policy_id == ^leave_policy_id,
        where: entitlement.effective_from <= ^range.last,
        where: is_nil(entitlement.effective_to) or entitlement.effective_to >= ^range.first,
        order_by: [leave_type.position, entitlement.leave_type_id, entitlement.effective_from],
        preload: [leave_type: leave_type]
    )
  end
end
