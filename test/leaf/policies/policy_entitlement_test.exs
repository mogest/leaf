defmodule Leaf.Policies.PolicyEntitlementTest do
  use Leaf.DataCase, async: true

  alias Leaf.Fixtures
  alias Leaf.Policies.PolicyEntitlement

  @base %{
    leave_policy_id: Ecto.UUID.generate(),
    leave_type_id: Ecto.UUID.generate(),
    effective_from: ~D[2004-01-01],
    pro_rated_by_fte: true,
    expiry_rule: :never,
    allow_negative: false
  }

  @quarterly %{
    amount_source: :fixed,
    grant_amount: "8",
    grant_basis: :calendar_year,
    grant_period: :quarter,
    grant_timing: :period_start
  }

  defp changeset(attrs),
    do: PolicyEntitlement.changeset(%PolicyEntitlement{}, Map.merge(@base, attrs))

  test "accepts a fixed grant with its period and timing" do
    assert changeset(@quarterly).valid?
  end

  test "requires the grant group when the amount is fixed" do
    errors = errors_on(changeset(%{amount_source: :fixed}))

    assert errors.grant_amount == ["can't be blank"]
    assert errors.grant_basis == ["can't be blank"]
    assert errors.grant_period == ["can't be blank"]
    assert errors.grant_timing == ["can't be blank"]
  end

  test "rejects a grant schedule when nothing is granted" do
    errors = errors_on(changeset(Map.put(@quarterly, :amount_source, :none)))

    assert errors.grant_amount == ["must be blank"]
    assert errors.grant_basis == ["must be blank"]
    assert errors.grant_period == ["must be blank"]
    assert errors.grant_timing == ["must be blank"]
  end

  test "unpaid leave grants nothing" do
    assert changeset(%{amount_source: :none}).valid?
  end

  test "the public holiday allowance is computed rather than configured" do
    attrs = %{
      amount_source: :public_holidays,
      grant_basis: :employment_date,
      grant_period: :year,
      grant_timing: :period_start
    }

    assert changeset(attrs).valid?
  end

  test "the public holiday allowance is computed over the person's leave year" do
    errors = errors_on(changeset(Map.put(@quarterly, :amount_source, :public_holidays)))

    assert errors.grant_amount == ["must be blank"]
    assert errors.grant_basis == ["is invalid"]
    assert errors.grant_period == ["is invalid"]
  end

  test "birthday leave is granted yearly" do
    attrs = Map.merge(@quarterly, %{grant_basis: :birthday, grant_period: :quarter})

    assert errors_on(changeset(attrs)).grant_period == ["is invalid"]
  end

  test "a capped rollover needs a cap and no expiry window" do
    attrs = Map.merge(@quarterly, %{expiry_rule: :cap, expiry_window_days: 14})
    errors = errors_on(changeset(attrs))

    assert errors.rollover_cap == ["can't be blank"]
    assert errors.expiry_window_days == ["must be blank"]
  end

  test "a lapsing window needs a window" do
    attrs = Map.put(@quarterly, :expiry_rule, :window)

    assert errors_on(changeset(attrs)).expiry_window_days == ["can't be blank"]
  end

  test "grants may stop before the entitlement ends" do
    attrs = Map.merge(@quarterly, %{granted_to: ~D[2006-12-31], effective_to: ~D[2007-03-31]})

    assert changeset(attrs).valid?
  end

  test "grants may not outlive the entitlement" do
    attrs = Map.merge(@quarterly, %{granted_to: ~D[2007-01-01], effective_to: ~D[2006-12-31]})

    assert errors_on(changeset(attrs)).effective_to == ["must not be before granted_to"]
  end

  test "a policy cannot offer the same leave type over two overlapping windows" do
    organisation = Fixtures.organisation()
    policy = Fixtures.leave_policy(%{organisation_id: organisation.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})
    attrs = Map.merge(@quarterly, %{leave_policy_id: policy.id, leave_type_id: leave_type.id})

    assert {:ok, _withdrawn} =
             Repo.insert(changeset(Map.put(attrs, :effective_to, ~D[2005-12-31])))

    assert {:error, changeset} = Repo.insert(changeset(attrs))

    assert errors_on(changeset).effective_from == [
             "overlaps another entitlement for this leave type"
           ]

    reoffered = Map.put(attrs, :effective_from, ~D[2006-01-01])

    assert {:ok, _entitlement} = Repo.insert(changeset(reoffered))
  end
end
