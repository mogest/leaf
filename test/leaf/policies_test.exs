defmodule Leaf.PoliciesTest do
  use Leaf.DataCase, async: true

  alias Leaf.Fixtures
  alias Leaf.Policies

  setup do
    organisation = Fixtures.organisation()
    policy = Fixtures.leave_policy(%{organisation_id: organisation.id})
    annual = Fixtures.leave_type(%{organisation_id: organisation.id})

    quarterly =
      Fixtures.leave_type(%{
        organisation_id: organisation.id,
        name: "Quarterly leave",
        position: 2
      })

    %{organisation: organisation, policy: policy, annual: annual, quarterly: quarterly}
  end

  defp quarterly_entitlement(policy, leave_type, attrs) do
    Fixtures.policy_entitlement(
      Map.merge(
        %{
          leave_policy_id: policy.id,
          leave_type_id: leave_type.id,
          grant_amount: "8",
          grant_basis: :calendar_year,
          grant_period: :quarter,
          grant_timing: :period_start,
          expiry_rule: :grant_period_end
        },
        attrs
      )
    )
  end

  test "entitlements come back per leave type, oldest first, with the type loaded", context do
    %{policy: policy, annual: annual, quarterly: quarterly} = context

    ongoing =
      Fixtures.policy_entitlement(%{leave_policy_id: policy.id, leave_type_id: annual.id})

    withdrawn = quarterly_entitlement(policy, quarterly, %{effective_to: ~D[2025-12-31]})
    reoffered = quarterly_entitlement(policy, quarterly, %{effective_from: ~D[2026-01-01]})

    entitlements = Policies.entitlements(policy.id, Date.range(~D[2025-12-01], ~D[2026-01-31]))

    assert Enum.map(entitlements, & &1.id) == [ongoing.id, withdrawn.id, reoffered.id]

    assert Enum.map(entitlements, & &1.leave_type.name) == [
             "Annual leave",
             "Quarterly leave",
             "Quarterly leave"
           ]
  end

  test "an entitlement whose life has ended is left out", context do
    %{policy: policy, quarterly: quarterly} = context
    quarterly_entitlement(policy, quarterly, %{effective_to: ~D[2025-12-31]})
    reoffered = quarterly_entitlement(policy, quarterly, %{effective_from: ~D[2026-01-01]})

    entitlements = Policies.entitlements(policy.id, Date.range(~D[2026-01-01], ~D[2026-03-31]))

    assert Enum.map(entitlements, & &1.id) == [reoffered.id]
  end

  test "two types sharing a position keep their successions apart", context do
    %{organisation: organisation, policy: policy, annual: annual} = context

    other =
      Fixtures.leave_type(%{organisation_id: organisation.id, name: "Study leave", position: 1})

    for leave_type <- [annual, other], from <- [~D[2024-01-01], ~D[2026-01-01]] do
      Fixtures.policy_entitlement(%{
        leave_policy_id: policy.id,
        leave_type_id: leave_type.id,
        effective_from: from
      })
    end

    entitlements = Policies.entitlements(policy.id, Date.range(~D[2026-01-01], ~D[2026-03-31]))

    assert Enum.map(entitlements, & &1.leave_type.id) |> Enum.chunk_by(& &1) |> length() == 2
  end

  test "another policy's entitlements stay out of it", context do
    %{organisation: organisation, policy: policy, annual: annual} = context
    other = Fixtures.leave_policy(%{organisation_id: organisation.id, name: "Hybrid contractor"})
    Fixtures.policy_entitlement(%{leave_policy_id: other.id, leave_type_id: annual.id})

    assert Policies.entitlements(policy.id, Date.range(~D[2026-01-01], ~D[2026-03-31])) == []
  end
end
