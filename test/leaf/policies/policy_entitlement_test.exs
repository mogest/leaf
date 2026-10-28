defmodule Leaf.Policies.PolicyEntitlementTest do
  use Leaf.DataCase, async: true

  alias Leaf.Fixtures
  alias Leaf.Policies.PolicyEntitlement

  @base %{
    effective_from: ~D[2004-01-01],
    pro_rated_by_fte: true,
    expiry_rule: :never
  }

  @quarterly %{
    amount_source: :fixed,
    grant_amount: "8",
    grant_basis: :calendar_year,
    grant_period: :quarter,
    grant_timing: :period_start
  }

  # What an entitlement is for is not cast, so it goes on the struct as `Leaf.Policies` puts it
  # there. Most of these never reach the database and can pair a policy and a type that do not.
  defp changeset(attrs, pairing \\ %{}) do
    %PolicyEntitlement{
      leave_policy_id: Ecto.UUID.generate(),
      leave_type_id: Ecto.UUID.generate()
    }
    |> struct!(pairing)
    |> PolicyEntitlement.changeset(Map.merge(@base, attrs))
  end

  test "accepts a fixed grant with its period and timing" do
    assert changeset(@quarterly).valid?
  end

  test "a grant may be as large as it likes, up to what the column holds" do
    assert changeset(%{@quarterly | grant_amount: "99999999.99"}).valid?

    errors = errors_on(changeset(%{@quarterly | grant_amount: "1200000000"}))

    assert errors.grant_amount == ["must be less than or equal to 99999999.99"]
  end

  test "an expiry window is refused where it overflows its column rather than raising" do
    attrs = Map.merge(@quarterly, %{expiry_rule: :window, expiry_window_days: 99_999_999_999})

    assert errors_on(changeset(attrs)).expiry_window_days == [
             "must be less than or equal to 2147483647"
           ]
  end

  test "requires the grant group when the amount is fixed" do
    errors = errors_on(changeset(%{amount_source: :fixed}))

    assert errors.grant_amount == ["can't be blank"]
    assert errors.grant_basis == ["can't be blank"]
    assert errors.grant_period == ["can't be blank"]
    assert errors.grant_timing == ["can't be blank"]
  end

  test "an entitlement that grants nothing drops its grant schedule, pro-rating and rollover" do
    attrs =
      Map.merge(@quarterly, %{
        amount_source: :none,
        pro_rated_by_fte: true,
        expiry_rule: :cap,
        rollover_cap: "8"
      })

    changeset = changeset(attrs)

    assert changeset.valid?

    assert %{
             grant_amount: nil,
             grant_basis: nil,
             grant_period: nil,
             grant_timing: nil,
             pro_rated_by_fte: false,
             expiry_rule: :never,
             rollover_cap: nil
           } = apply_changes(changeset)
  end

  test "the public holiday allowance is computed rather than configured" do
    attrs = %{
      amount_source: :public_holidays,
      grant_basis: :employment_date,
      grant_period: :year,
      grant_timing: :period_start
    }

    assert changeset(attrs).valid?
    assert apply_changes(changeset(attrs)).grant_timing == :period_start
  end

  test "a public holiday allowance on a shared year takes its amount from the calendar as it falls" do
    attrs = Map.merge(@quarterly, %{amount_source: :public_holidays, grant_basis: :calendar_year})
    changeset = changeset(attrs)

    assert changeset.valid?
    assert %{grant_amount: nil, grant_timing: :daily} = apply_changes(changeset)
  end

  test "birthday leave is granted yearly" do
    attrs = Map.put(@quarterly, :grant_basis, :birthday)

    assert apply_changes(changeset(attrs)).grant_period == :year
  end

  test "only a fixed amount qualifies, on any alignment" do
    qualifying = Map.put(@quarterly, :qualifying_months, 24)

    assert apply_changes(changeset(qualifying)).qualifying_months == 24

    assert errors_on(changeset(%{qualifying | qualifying_months: 0})).qualifying_months == [
             "must be greater than 0"
           ]

    allowance = %{qualifying | amount_source: :public_holidays, grant_amount: nil}

    for attrs <- [allowance, %{qualifying | amount_source: :none}] do
      assert apply_changes(changeset(attrs)).qualifying_months == nil
    end
  end

  test "any leave may wait on months of service before it is taken" do
    assert changeset(%{amount_source: :none, takeable_after_months: 24}).valid?

    assert errors_on(changeset(%{amount_source: :none, takeable_after_months: 0})) ==
             %{takeable_after_months: ["must be greater than 0"]}
  end

  test "a rollover rule needs its own cap or window and drops the other" do
    assert errors_on(changeset(Map.put(@quarterly, :expiry_rule, :cap))) ==
             %{rollover_cap: ["can't be blank"]}

    assert errors_on(changeset(Map.put(@quarterly, :expiry_rule, :window))) ==
             %{expiry_window_days: ["can't be blank"]}

    both = Map.merge(@quarterly, %{rollover_cap: "8", expiry_window_days: 14})

    assert %{rollover_cap: %Decimal{}, expiry_window_days: nil} =
             apply_changes(changeset(Map.put(both, :expiry_rule, :cap)))

    assert %{rollover_cap: nil, expiry_window_days: 14} =
             apply_changes(changeset(Map.put(both, :expiry_rule, :window)))

    for rule <- [:never, :grant_period_end] do
      assert %{rollover_cap: nil, expiry_window_days: nil} =
               apply_changes(changeset(Map.put(both, :expiry_rule, rule)))
    end
  end

  test "an unpaid leave allowance is only for a fixed amount accrued daily" do
    daily = %{@quarterly | grant_timing: :daily}

    assert changeset(Map.put(daily, :suspension_allowance_weeks, "1")).valid?

    assert apply_changes(changeset(Map.put(@quarterly, :suspension_allowance_weeks, "1"))).suspension_allowance_weeks ==
             nil
  end

  test "monthly accrual is only for a fixed yearly amount" do
    yearly = Map.merge(@quarterly, %{grant_period: :year, grant_timing: :monthly})

    assert %{grant_timing: :monthly, suspension_allowance_weeks: %Decimal{}} =
             apply_changes(changeset(Map.put(yearly, :suspension_allowance_weeks, "1")))

    assert apply_changes(changeset(%{yearly | grant_period: :quarter})).grant_timing == :daily

    holidays = %{yearly | amount_source: :public_holidays, grant_basis: :employment_date}
    assert apply_changes(changeset(holidays)).grant_timing == :daily
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
    pairing = %{leave_policy_id: policy.id, leave_type_id: leave_type.id}
    withdrawn = Map.put(@quarterly, :effective_to, ~D[2005-12-31])

    assert {:ok, _withdrawn} = Repo.insert(changeset(withdrawn, pairing))
    assert {:error, changeset} = Repo.insert(changeset(@quarterly, pairing))

    assert errors_on(changeset).effective_from == [
             "overlaps another entitlement for this leave type"
           ]

    reoffered = Map.put(@quarterly, :effective_from, ~D[2006-01-01])

    assert {:ok, _entitlement} = Repo.insert(changeset(reoffered, pairing))
  end

  test "new terms may take over the day after the old ones stop granting" do
    organisation = Fixtures.organisation()
    policy = Fixtures.leave_policy(%{organisation_id: organisation.id})
    leave_type = Fixtures.leave_type(%{organisation_id: organisation.id})
    pairing = %{leave_policy_id: policy.id, leave_type_id: leave_type.id}

    # Granting stops at the turn of the year, but the balance it granted stays spendable, so the
    # row's life runs on and it is only the grant windows that may not overlap.
    granting = Map.put(@quarterly, :granted_to, ~D[2005-12-31])

    assert {:ok, _granting} = Repo.insert(changeset(granting, pairing))
    assert {:error, changeset} = Repo.insert(changeset(granting, pairing))

    assert errors_on(changeset).effective_from == [
             "overlaps another entitlement for this leave type"
           ]

    successor = Map.put(@quarterly, :effective_from, ~D[2006-01-01])

    assert {:ok, _successor} = Repo.insert(changeset(successor, pairing))
  end
end
