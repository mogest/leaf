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
  alias Leaf.Dates
  alias Leaf.Leave
  alias Leaf.Org.Organisation
  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.Policies.Granting
  alias Leaf.Policies.LeavePolicy
  alias Leaf.Policies.LeaveType
  alias Leaf.Policies.PolicyEntitlement
  alias Leaf.Repo

  # An entitlement with no end governs everything after it, and leave can be filed years ahead, so
  # the window it could have been drawn on within has to be closed somewhere past all of it.
  @forever ~D[9999-12-31]

  @doc "Creates a leave type."
  @spec create_leave_type(Organisation.t(), Person.t() | nil, map()) ::
          Audit.written(LeaveType.t())
  def create_leave_type(organisation, actor, attrs) do
    %LeaveType{organisation_id: organisation.id}
    |> LeaveType.changeset(attrs)
    |> Audit.write("leave_type.created", actor)
  end

  @doc "The changeset a new leave type's form binds to."
  @spec change_leave_type(Organisation.t(), map()) :: Ecto.Changeset.t()
  def change_leave_type(%Organisation{} = organisation, attrs) do
    LeaveType.changeset(%LeaveType{organisation_id: organisation.id}, attrs)
  end

  @doc "The changeset a new leave policy's form binds to."
  @spec change_leave_policy(Organisation.t(), map()) :: Ecto.Changeset.t()
  def change_leave_policy(%Organisation{} = organisation, attrs) do
    LeavePolicy.changeset(%LeavePolicy{organisation_id: organisation.id}, attrs)
  end

  @doc "The changeset a new entitlement's form binds to."
  @spec change_entitlement(LeavePolicy.t(), LeaveType.t() | nil, map()) :: Ecto.Changeset.t()
  def change_entitlement(policy, leave_type, attrs) do
    PolicyEntitlement.changeset(
      %PolicyEntitlement{leave_policy_id: policy.id, leave_type_id: leave_type && leave_type.id},
      attrs
    )
  end

  @doc "Amends a leave type."
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

  @doc "Amends a leave policy."
  @spec update_leave_policy(LeavePolicy.t(), Person.t() | nil, map()) ::
          Audit.written(LeavePolicy.t())
  def update_leave_policy(policy, actor, attrs) do
    policy |> LeavePolicy.changeset(attrs) |> Audit.write("leave_policy.updated", actor)
  end

  @doc """
  Stops offering a leave type or a leave policy.

  Withdrawing is archiving, not deleting: nothing new is set up against it, and everything already
  drawing on it goes on as it was.
  """
  @spec withdraw(LeaveType.t(), Person.t() | nil) :: Audit.written(LeaveType.t())
  @spec withdraw(LeavePolicy.t(), Person.t() | nil) :: Audit.written(LeavePolicy.t())
  def withdraw(record, actor) do
    archived(record, actor, DateTime.truncate(DateTime.utc_now(), :second), "withdrawn")
  end

  @doc "Offers a withdrawn leave type or leave policy again."
  @spec reoffer(LeaveType.t(), Person.t() | nil) :: Audit.written(LeaveType.t())
  @spec reoffer(LeavePolicy.t(), Person.t() | nil) :: Audit.written(LeavePolicy.t())
  def reoffer(record, actor), do: archived(record, actor, nil, "reoffered")

  defp archived(%LeaveType{} = leave_type, actor, at, action) do
    leave_type
    |> LeaveType.changeset(%{archived_at: at})
    |> Audit.write("leave_type.#{action}", actor)
  end

  defp archived(%LeavePolicy{} = policy, actor, at, action) do
    policy
    |> LeavePolicy.changeset(%{archived_at: at})
    |> Audit.write("leave_policy.#{action}", actor)
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

  Closing one means setting `effective_to`, which lapses what it granted. Changing its terms means
  setting `granted_to` and opening the next row the day after: two grant windows for one leave type
  under one policy may not overlap, but their lives may.

  Once leave has been taken against one, those two dates are all that may change: anything else is
  refused with `{:error, :drawn_on}`, since it would rewrite what the leave already taken drew on.
  """
  @spec update_entitlement(PolicyEntitlement.t(), Person.t() | nil, map()) ::
          Audit.written(PolicyEntitlement.t()) | {:error, :drawn_on}
  def update_entitlement(entitlement, actor, attrs) do
    write = fn entitlement ->
      entitlement
      |> PolicyEntitlement.changeset(attrs)
      |> Audit.write("policy_entitlement.updated", actor)
    end

    amended(entitlement, PolicyEntitlement.changeset(entitlement, attrs), write)
  end

  defp amended(_entitlement, %{valid?: false} = changeset, _write), do: {:error, changeset}

  defp amended(entitlement, changeset, write) do
    case Map.keys(changeset.changes) -- [:granted_to, :effective_to] do
      [] -> write.(entitlement)
      _terms -> unless_drawn_on(entitlement, write)
    end
  end

  @doc """
  Removes an entitlement outright.

  For one that should never have existed. One leave has already been taken against is refused with
  `{:error, :drawn_on}`: what it granted has been spent, and taking it away leaves the people on
  the policy owing a balance with nothing to account for it. An entitlement that ran and is now
  over is closed with `effective_to` instead, so what it granted still has something to account
  for it.
  """
  @spec delete_entitlement(PolicyEntitlement.t(), Person.t() | nil) ::
          Audit.written(PolicyEntitlement.t()) | {:error, :drawn_on}
  def delete_entitlement(entitlement, actor) do
    unless_drawn_on(entitlement, &Audit.delete(&1, "policy_entitlement.deleted", actor))
  end

  # The entitlement is read again inside the lock, so that the check and the write are both about
  # the row as it stands rather than as the caller last saw it.
  defp unless_drawn_on(entitlement, write) do
    people = People.on_policy(entitlement.leave_policy_id)

    Leave.serialised(Enum.map(people, & &1.id), fn ->
      {:ok, entitlement} = Repo.fetch(PolicyEntitlement, entitlement.id)

      if drawn_on?(people, entitlement), do: {:error, :drawn_on}, else: write.(entitlement)
    end)
  end

  # Leave draws on a pool rather than on the row that filled it, so what counts as having drawn on
  # an entitlement is leave of its type taken by somebody its policy governed while it was in force.
  defp drawn_on?(people, entitlement) do
    window = Date.range(entitlement.effective_from, entitlement.effective_to || @forever)

    Enum.any?(people, &drawn_on?(&1, entitlement, window))
  end

  defp drawn_on?(person, entitlement, window) do
    person
    |> People.leave_policy_segments(window)
    |> Enum.filter(fn {_span, policy} -> policy.id == entitlement.leave_policy_id end)
    |> Enum.any?(fn {span, _policy} ->
      Leave.taken?(person, entitlement.leave_type_id, span)
    end)
  end

  @doc "Every leave type the organisation offers, withdrawn ones included, in its own order then by name."
  @spec leave_types(Ecto.UUID.t()) :: [LeaveType.t()]
  def leave_types(organisation_id), do: Repo.all(all_leave_types(organisation_id))

  @doc "The leave types still offered, which are the ones new configuration may be set up against."
  @spec leave_types_offered(Ecto.UUID.t()) :: [LeaveType.t()]
  def leave_types_offered(organisation_id) do
    Repo.all(from type in all_leave_types(organisation_id), where: is_nil(type.archived_at))
  end

  @doc "Every leave policy the organisation offers, withdrawn ones included, by name."
  @spec leave_policies(Ecto.UUID.t()) :: [LeavePolicy.t()]
  def leave_policies(organisation_id), do: Repo.all(all_leave_policies(organisation_id))

  @doc "The leave policies still offered, which are the ones somebody may be put on."
  @spec leave_policies_offered(Ecto.UUID.t()) :: [LeavePolicy.t()]
  def leave_policies_offered(organisation_id) do
    Repo.all(
      from policy in all_leave_policies(organisation_id), where: is_nil(policy.archived_at)
    )
  end

  defp all_leave_types(organisation_id) do
    from type in LeaveType,
      where: type.organisation_id == ^organisation_id,
      order_by: [type.position, type.name]
  end

  defp all_leave_policies(organisation_id) do
    from policy in LeavePolicy,
      where: policy.organisation_id == ^organisation_id,
      order_by: policy.name
  end

  @doc "The leave type, or `:error` where no such type exists."
  @spec fetch_leave_type(Ecto.UUID.t()) :: {:ok, LeaveType.t()} | :error
  def fetch_leave_type(id), do: Repo.fetch(LeaveType, id)

  @doc "The leave policy, or `:error` where no such policy exists."
  @spec fetch_leave_policy(Ecto.UUID.t()) :: {:ok, LeavePolicy.t()} | :error
  def fetch_leave_policy(id), do: Repo.fetch(LeavePolicy, id)

  @doc "One of the policy's entitlements with its leave type, or `:error` where it is not on it."
  @spec fetch_entitlement(LeavePolicy.t(), Ecto.UUID.t()) :: {:ok, PolicyEntitlement.t()} | :error
  def fetch_entitlement(policy, id) do
    with {:ok, entitlement} <- Repo.fetch(PolicyEntitlement, id, leave_policy_id: policy.id) do
      {:ok, Repo.preload(entitlement, :leave_type)}
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

  @doc "What `grant_windows/3` reads of a policy, to load it for many policies at once."
  @spec entitlements_preload() :: keyword()
  def entitlements_preload do
    [
      entitlements:
        from(entitlement in PolicyEntitlement,
          order_by: entitlement.effective_from,
          preload: :leave_type
        )
    ]
  end

  @doc """
  Each grant period of each entitlement the person's policies grant over `range`, with its entitlement.

  `range` is the stretch of their history being asked about. Whether a block grant lands turns on
  where its period opens, so a range starting part-way through a period has no block for it.
  """
  @spec grant_windows(Person.t(), Organisation.t(), Date.Range.t()) :: [Granting.window()]
  def grant_windows(person, organisation, range) do
    for {assigned, policy} <- People.leave_policy_segments(person, range),
        entitlement <- Repo.preload(policy, entitlements_preload()).entitlements,
        window <- Granting.windows(entitlement, person, organisation, assigned),
        do: window
  end

  @doc """
  The ranges a grant is measured over, or none where it grants nothing.

  `granting` is the part of `period` it grants over. An accrual is measured over that. A block grant
  is measured over its whole grant period, which can open before `granting` does and run past the
  date being asked about, and only one whose `granting` starts when its period does lands at all —
  which is what leaves someone who joined part-way through a period without one until the next
  period starts. The one block measured in something other than dates — a share of the holiday
  calendar — stops where the person's employment does.
  """
  @spec measured(PolicyEntitlement.t(), Date.Range.t(), Date.Range.t() | nil, Date.t() | nil) ::
          [Date.Range.t()]
  def measured(entitlement, period, granting, employed_to) do
    Granting.measured(entitlement, period, granting, employed_to)
  end

  @doc """
  The stretches of `range` over which the person's policy credits them public holidays instead of granting them off.

  These are exactly the dates the allowance's grants are measured over, as `measured/4` gives them,
  so a holiday counts as worked only where the allowance credits it. One outside them — after the
  allowance stops granting, or in a period part-way through which it started, so no block landed —
  is a day off like anybody else's rather than a working day with nothing to pay for it.

  Grants are read from the start of the person's employment rather than from `range`, since whether
  a block lands turns on where its period opens, which can be well before `range` does.
  """
  @spec crediting(Person.t(), Date.Range.t()) :: [Date.Range.t()]
  def crediting(person, range) do
    %{organisation: organisation} = person = People.dated(person)

    case Dates.bounded(
           person.employment_start_date,
           Dates.earliest(range.last, person.employment_end_date)
         ) do
      :error -> []
      {:ok, employed} -> crediting(person, organisation, employed, range)
    end
  end

  defp crediting(person, organisation, employed, range) do
    for %{entitlement: %{amount_source: :public_holidays} = held} = window <-
          grant_windows(person, organisation, employed),
        measured <- measured(held, window.period, window.granting, person.employment_end_date),
        {:ok, credited} <- [Dates.intersect(range, measured.first, measured.last)],
        do: credited
  end

  defp of_policy(leave_policy_id) do
    from entitlement in PolicyEntitlement,
      join: leave_type in assoc(entitlement, :leave_type),
      where: entitlement.leave_policy_id == ^leave_policy_id,
      order_by: [
        leave_type.position,
        leave_type.name,
        entitlement.leave_type_id,
        entitlement.effective_from
      ],
      preload: [leave_type: leave_type]
  end
end
