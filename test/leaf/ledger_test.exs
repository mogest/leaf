defmodule Leaf.LedgerTest do
  use Leaf.DataCase, async: true

  alias Leaf.Fixtures
  alias Leaf.Leave.Day
  alias Leaf.Ledger
  alias Leaf.People

  @started ~D[2024-03-04]

  setup do
    organisation = Fixtures.organisation()
    policy = Fixtures.leave_policy(%{organisation_id: organisation.id})

    person =
      Fixtures.person(%{organisation_id: organisation.id, birth_date: ~D[1990-08-10]})

    Fixtures.policy_assignment(%{
      person_id: person.id,
      leave_policy_id: policy.id,
      effective_from: @started
    })

    %{organisation: organisation, policy: policy, person: person}
  end

  defp leave_type(context, attrs) do
    Fixtures.leave_type(Map.merge(%{organisation_id: context.organisation.id}, attrs))
  end

  defp entitlement(context, leave_type, attrs) do
    Fixtures.policy_entitlement(
      Map.merge(
        %{leave_policy_id: context.policy.id, leave_type_id: leave_type.id},
        attrs
      )
    )
  end

  defp weekdays(person, from, hours) do
    Fixtures.work_pattern(%{
      person_id: person.id,
      effective_from: from,
      monday_hours: hours,
      tuesday_hours: hours,
      wednesday_hours: hours,
      thursday_hours: hours,
      friday_hours: hours
    })
  end

  # 40 hours, which is the organisation's full week.
  defp full_time(person), do: weekdays(person, @started, "8")

  # 36 hours: 0.9 of it.
  defp part_time(person), do: weekdays(person, @started, "7.2")

  defp take(person, leave_type, date, amount, unit) do
    Fixtures.leave_request(%{
      person_id: person.id,
      days: [%{leave_type_id: leave_type.id, date: date, amount: amount, unit: unit}]
    })
  end

  defp day(leave_type, date, amount, unit) do
    %Day{leave_type_id: leave_type.id, date: date, amount: Decimal.new(amount), unit: unit}
  end

  defp observes(context, person, dates) do
    calendar = Fixtures.holiday_calendar(%{organisation_id: context.organisation.id})

    Enum.each(dates, &Fixtures.public_holiday(%{holiday_calendar_id: calendar.id, date: &1}))

    Fixtures.calendar_assignment(%{
      person_id: person.id,
      holiday_calendar_id: calendar.id,
      effective_from: @started
    })
  end

  defp early_starter(context, attrs) do
    started_on = ~D[2023-06-01]

    person =
      Fixtures.person(
        Map.merge(
          %{organisation_id: context.organisation.id, employment_start_date: started_on},
          attrs
        )
      )

    weekdays(person, started_on, "8")

    Fixtures.policy_assignment(%{
      person_id: person.id,
      leave_policy_id: context.policy.id,
      effective_from: started_on
    })

    person
  end

  defp statement(person, leave_type, as_at) do
    {:ok, statement} = Ledger.fetch_statement(person, leave_type.id, as_at)

    statement
  end

  defp movements(statement) do
    Enum.map(statement.movements, &{&1.kind, &1.date, Decimal.round(&1.amount, 2), &1.expires_on})
  end

  defp lots(statement) do
    Enum.map(statement.lots, &{Decimal.round(&1.amount, 2), &1.expires_on})
  end

  test "annual leave accrues across its year, pro-rated by the hours worked", context do
    part_time(context.person)
    annual = leave_type(context, %{})
    entitlement(context, annual, %{grant_amount: "200"})

    whole_year = statement(context.person, annual, ~D[2025-03-03])
    part_year = statement(context.person, annual, ~D[2024-09-03])

    assert movements(whole_year) == [{:accrual, ~D[2025-03-03], Decimal.new("180.00"), nil}]
    assert Decimal.equal?(whole_year.balance, "180.00")
    assert Decimal.equal?(part_year.balance, "90.74")
  end

  test "a day off is worth what a day is worth when it comes round", context do
    person = context.person
    full_time(person)
    weekdays(person, ~D[2024-04-01], "7")
    annual = leave_type(context, %{})
    entitlement(context, annual, %{grant_amount: "200"})

    # Both asked for on eight-hour days, both taken after the person went down to seven.
    take(person, annual, ~D[2024-05-01], "1", :days)
    take(person, annual, ~D[2024-05-02], "8", :hours)

    taken = Enum.filter(statement(person, annual, ~D[2024-05-31]).movements, &(&1.kind == :taken))

    assert Enum.map(taken, &Decimal.round(&1.amount, 2)) ==
             [Decimal.new("-7.00"), Decimal.new("-8.00")]
  end

  test "a block grant lands whole at the start of its period, or not at all", context do
    part_time(context.person)
    quarterly = leave_type(context, %{name: "Quarterly leave", position: 2})

    entitlement(context, quarterly, %{
      grant_amount: "8",
      grant_basis: :calendar_year,
      grant_period: :quarter,
      grant_timing: :period_start,
      expiry_rule: :grant_period_end
    })

    joined_mid_quarter = statement(context.person, quarterly, ~D[2024-03-31])
    first_full_quarter = statement(context.person, quarterly, ~D[2024-07-01])

    assert movements(joined_mid_quarter) == []
    assert Decimal.equal?(joined_mid_quarter.balance, "0.00")

    assert movements(first_full_quarter) == [
             {:grant, ~D[2024-04-01], Decimal.new("7.20"), ~D[2024-06-30]},
             {:expiry, ~D[2024-06-30], Decimal.new("-7.20"), nil},
             {:grant, ~D[2024-07-01], Decimal.new("7.20"), ~D[2024-09-30]}
           ]

    assert Decimal.equal?(first_full_quarter.balance, "7.20")
  end

  test "an entitlement can hang off the organisation's year rather than the person's", context do
    person = context.person
    full_time(person)
    training = leave_type(context, %{name: "Training leave", position: 2})

    entitlement(context, training, %{
      grant_amount: "16",
      grant_basis: :organisation_year,
      grant_timing: :period_start,
      pro_rated_by_fte: false,
      expiry_rule: :grant_period_end
    })

    # The organisation's year starts in April, so this runs to a different clock from the person's
    # own anniversary and from the calendar year.
    assert movements(statement(person, training, ~D[2025-04-01])) == [
             {:grant, ~D[2024-04-01], Decimal.new("16.00"), ~D[2025-03-31]},
             {:expiry, ~D[2025-03-31], Decimal.new("-16.00"), nil},
             {:grant, ~D[2025-04-01], Decimal.new("16.00"), ~D[2026-03-31]}
           ]
  end

  test "leave draws on the lot that lapses soonest", context do
    person = context.person
    full_time(person)
    carried = leave_type(context, %{name: "Carried leave", position: 2})
    entry = %{person_id: person.id, leave_type_id: carried.id}

    Fixtures.balance_entry(Map.put(entry, :amount, "40"))

    Fixtures.balance_entry(
      Map.merge(entry, %{
        date: ~D[2024-04-01],
        kind: :adjustment,
        amount: "10",
        expires_on: ~D[2024-06-30],
        reason: "Top-up to use by June"
      })
    )

    take(person, carried, ~D[2024-05-01], "8", :hours)

    before_lapse = statement(person, carried, ~D[2024-06-29])
    after_lapse = statement(person, carried, ~D[2024-06-30])

    assert lots(before_lapse) == [
             {Decimal.new("2.00"), ~D[2024-06-30]},
             {Decimal.new("40.00"), nil}
           ]

    assert Decimal.equal?(before_lapse.balance, "42.00")

    assert List.last(movements(after_lapse)) ==
             {:expiry, ~D[2024-06-30], Decimal.new("-2.00"), nil}

    assert Decimal.equal?(after_lapse.balance, "40.00")
  end

  test "leave approved for later is spent already, and lapses nothing that has not lapsed",
       context do
    person = context.person
    full_time(person)
    carried = leave_type(context, %{name: "Carried leave", position: 2})
    entry = %{person_id: person.id, leave_type_id: carried.id}

    Fixtures.balance_entry(Map.put(entry, :amount, "40"))

    Fixtures.balance_entry(
      Map.merge(entry, %{
        date: ~D[2024-04-01],
        kind: :adjustment,
        amount: "10",
        expires_on: ~D[2024-06-30],
        reason: "Top-up to use by June"
      })
    )

    take(person, carried, ~D[2024-08-01], "8", :hours)

    statement = statement(person, carried, ~D[2024-05-01])

    assert movements(statement) == [
             {:opening_balance, ~D[2024-01-01], Decimal.new("40.00"), nil},
             {:adjustment, ~D[2024-04-01], Decimal.new("10.00"), ~D[2024-06-30]},
             {:taken, ~D[2024-08-01], Decimal.new("-8.00"), nil}
           ]

    assert lots(statement) == [{Decimal.new("2.00"), ~D[2024-06-30]}, {Decimal.new("40.00"), nil}]
    assert Decimal.equal?(statement.balance, "42.00")
  end

  test "a capped leave type is trimmed to the cap, taking from the lots with longest to run",
       context do
    person = context.person
    full_time(person)
    sick = leave_type(context, %{name: "Sick leave", unit: :days, position: 2})

    entitlement(context, sick, %{
      grant_amount: "20",
      grant_timing: :period_start,
      pro_rated_by_fte: false,
      expiry_rule: :cap,
      rollover_cap: "25"
    })

    Fixtures.balance_entry(%{
      person_id: person.id,
      leave_type_id: sick.id,
      date: ~D[2025-06-01],
      kind: :adjustment,
      amount: "5",
      expires_on: ~D[2026-06-30],
      reason: "Alternative holiday worked"
    })

    take(person, sick, ~D[2024-05-01], "1", :days)

    statement = statement(person, sick, ~D[2026-03-03])

    assert movements(statement) == [
             {:grant, @started, Decimal.new("20.00"), nil},
             {:taken, ~D[2024-05-01], Decimal.new("-1.00"), nil},
             {:grant, ~D[2025-03-04], Decimal.new("20.00"), nil},
             {:adjustment, ~D[2025-06-01], Decimal.new("5.00"), ~D[2026-06-30]},
             {:rollover_cap, ~D[2026-03-03], Decimal.new("-19.00"), nil}
           ]

    assert lots(statement) == [
             {Decimal.new("5.00"), ~D[2026-06-30]},
             {Decimal.new("20.00"), nil}
           ]

    assert Decimal.equal?(statement.balance, "25.00")
  end

  test "birthday leave lapses a window after the birthday, and needs a birth date", context do
    person = context.person
    full_time(person)
    birthday = leave_type(context, %{name: "Birthday leave", unit: :days, position: 2})

    entitlement(context, birthday, %{
      grant_amount: "1",
      grant_basis: :birthday,
      grant_timing: :period_start,
      pro_rated_by_fte: false,
      expiry_rule: :window,
      expiry_window_days: 14
    })

    unlapsed = statement(person, birthday, ~D[2024-08-23])
    lapsed = statement(person, birthday, ~D[2024-08-24])

    assert lots(unlapsed) == [{Decimal.new("1.00"), ~D[2024-08-24]}]

    assert movements(lapsed) == [
             {:grant, ~D[2024-08-10], Decimal.new("1.00"), ~D[2024-08-24]},
             {:expiry, ~D[2024-08-24], Decimal.new("-1.00"), nil}
           ]

    without_birth_date = Fixtures.person(%{organisation_id: context.organisation.id})
    full_time(without_birth_date)

    Fixtures.policy_assignment(%{
      person_id: without_birth_date.id,
      leave_policy_id: context.policy.id,
      effective_from: @started
    })

    assert Ledger.fetch_statement(without_birth_date, birthday.id, ~D[2024-08-23]) == :error
  end

  test "a public holiday allowance credits the person's share of the year's calendar", context do
    person = context.person
    part_time(person)
    in_hours = leave_type(context, %{name: "Public holiday allowance", position: 2})
    in_days = leave_type(context, %{name: "Public holiday days", unit: :days, position: 3})

    allowance = %{amount_source: :public_holidays, grant_amount: nil, grant_timing: :period_start}

    entitlement(context, in_hours, allowance)
    entitlement(context, in_days, allowance)
    observes(context, person, [~D[2024-01-01], ~D[2024-04-25], ~D[2024-12-25], ~D[2025-01-01]])

    # Three holidays fall in the leave year, at 0.9 FTE and an eight hour standard day.
    assert movements(statement(person, in_hours, ~D[2024-04-01])) ==
             [{:grant, @started, Decimal.new("21.60"), nil}]

    assert movements(statement(person, in_days, ~D[2024-04-01])) ==
             [{:grant, @started, Decimal.new("2.70"), nil}]
  end

  test "a public holiday allowance is not worked out over an unknown calendar", context do
    person = context.person
    part_time(person)
    allowance = leave_type(context, %{name: "Public holiday allowance", position: 2})

    entitlement(context, allowance, %{
      amount_source: :public_holidays,
      grant_amount: nil,
      grant_timing: :period_start
    })

    calendar = Fixtures.holiday_calendar(%{organisation_id: context.organisation.id})
    Fixtures.public_holiday(%{holiday_calendar_id: calendar.id, date: ~D[2024-12-25]})

    Fixtures.calendar_assignment(%{
      person_id: person.id,
      holiday_calendar_id: calendar.id,
      effective_from: ~D[2024-06-01]
    })

    assert_raise RuntimeError, ~r/no holiday calendar in force on 2024-03-04/, fn ->
      Ledger.statements(person, ~D[2024-04-01])
    end
  end

  test "a daily public holiday allowance credits each holiday as it falls", context do
    person = context.person
    part_time(person)
    allowance = leave_type(context, %{name: "Public holiday allowance", position: 2})

    entitlement(context, allowance, %{amount_source: :public_holidays, grant_amount: nil})
    observes(context, person, [~D[2024-04-25], ~D[2024-12-25]])

    statement = statement(person, allowance, ~D[2024-04-30])

    assert movements(statement) == [{:accrual, ~D[2024-04-30], Decimal.new("7.20"), nil}]
  end

  test "a public holiday allowance may be counted over a shared year", context do
    person = context.person
    part_time(person)
    allowance = leave_type(context, %{name: "Public holiday allowance", position: 2})

    entitlement(context, allowance, %{
      amount_source: :public_holidays,
      grant_amount: nil,
      grant_basis: :calendar_year
    })

    observes(context, person, [~D[2024-01-01], ~D[2024-04-25], ~D[2024-12-25], ~D[2025-01-01]])

    # The year turns on 1 January rather than the March anniversary, and the holiday before the
    # person started is none of theirs.
    assert movements(statement(person, allowance, ~D[2025-01-31])) == [
             {:accrual, ~D[2024-12-31], Decimal.new("14.40"), nil},
             {:accrual, ~D[2025-01-31], Decimal.new("7.20"), nil}
           ]
  end

  test "nothing accrues before tracking started or after employment ended", context do
    annual = leave_type(context, %{})
    entitlement(context, annual, %{grant_amount: "200", effective_from: ~D[2023-01-01]})

    employed = early_starter(context, %{})
    left = early_starter(context, %{employment_end_date: ~D[2024-04-30]})

    assert movements(statement(employed, annual, ~D[2024-05-31])) ==
             [{:accrual, ~D[2024-05-31], Decimal.new("83.06"), nil}]

    assert movements(statement(left, annual, ~D[2024-05-31])) ==
             [{:accrual, ~D[2024-04-30], Decimal.new("66.12"), nil}]
  end

  test "moving to another policy part-way through a year splits the accrual", context do
    person = context.person
    full_time(person)
    annual = leave_type(context, %{})
    entitlement(context, annual, %{grant_amount: "200"})

    senior = Fixtures.leave_policy(%{organisation_id: context.organisation.id, name: "Senior"})

    entitlement(%{context | policy: senior}, annual, %{
      grant_amount: "400",
      effective_from: ~D[2024-01-01]
    })

    Fixtures.policy_assignment(%{
      person_id: person.id,
      leave_policy_id: senior.id,
      effective_from: ~D[2024-09-01]
    })

    statement = statement(person, annual, ~D[2025-03-03])

    assert movements(statement) == [
             {:accrual, ~D[2024-08-31], Decimal.new("99.18"), nil},
             {:accrual, ~D[2025-03-03], Decimal.new("201.64"), nil}
           ]

    assert Decimal.equal?(statement.balance, "300.82")
  end

  test "changing hours part-way through a year splits the accrual too", context do
    person = context.person
    full_time(person)
    weekdays(person, ~D[2024-09-01], "4")
    annual = leave_type(context, %{})
    entitlement(context, annual, %{grant_amount: "200"})

    statement = statement(person, annual, ~D[2025-03-03])

    assert movements(statement) == [
             {:accrual, ~D[2024-08-31], Decimal.new("99.18"), nil},
             {:accrual, ~D[2025-03-03], Decimal.new("50.41"), nil}
           ]

    assert Decimal.equal?(statement.balance, "149.59")
  end

  test "granting can stop while the balance stays spendable, and lapses with it", context do
    person = context.person
    full_time(person)
    quarterly = leave_type(context, %{name: "Quarterly leave", position: 2})

    entitlement(context, quarterly, %{
      grant_amount: "8",
      grant_basis: :calendar_year,
      grant_period: :quarter,
      grant_timing: :period_start,
      pro_rated_by_fte: false,
      granted_to: ~D[2024-12-31],
      effective_to: ~D[2025-03-31]
    })

    wound_down = statement(person, quarterly, ~D[2025-03-30])
    ended = statement(person, quarterly, ~D[2025-03-31])

    assert lots(wound_down) == [
             {Decimal.new("8.00"), ~D[2025-03-31]},
             {Decimal.new("8.00"), ~D[2025-03-31]},
             {Decimal.new("8.00"), ~D[2025-03-31]}
           ]

    assert Decimal.equal?(wound_down.balance, "24.00")

    assert movements(ended) == [
             {:grant, ~D[2024-04-01], Decimal.new("8.00"), ~D[2025-03-31]},
             {:grant, ~D[2024-07-01], Decimal.new("8.00"), ~D[2025-03-31]},
             {:grant, ~D[2024-10-01], Decimal.new("8.00"), ~D[2025-03-31]},
             {:expiry, ~D[2025-03-31], Decimal.new("-8.00"), nil},
             {:expiry, ~D[2025-03-31], Decimal.new("-8.00"), nil},
             {:expiry, ~D[2025-03-31], Decimal.new("-8.00"), nil}
           ]

    assert Decimal.equal?(ended.balance, "0.00")
  end

  test "taking more than is held goes negative, and what arrives next pays it off", context do
    person = context.person
    full_time(person)
    bereavement = leave_type(context, %{name: "Bereavement leave", unit: :days, position: 2})

    entitlement(context, bereavement, %{
      amount_source: :none,
      grant_amount: nil,
      grant_basis: nil,
      grant_period: nil,
      grant_timing: nil,
      allow_negative: true
    })

    take(person, bereavement, ~D[2024-05-01], "1", :days)

    Fixtures.balance_entry(%{
      person_id: person.id,
      leave_type_id: bereavement.id,
      date: ~D[2024-06-01],
      kind: :adjustment,
      amount: "2",
      reason: "Allocated by agreement"
    })

    overdrawn = statement(person, bereavement, ~D[2024-05-31])
    paid_off = statement(person, bereavement, ~D[2024-06-30])

    assert lots(overdrawn) == []
    assert Decimal.equal?(overdrawn.balance, "-1.00")
    assert lots(paid_off) == [{Decimal.new("1.00"), nil}]
    assert Decimal.equal?(paid_off.balance, "1.00")
  end

  test "leave counts whenever it falls, and only a projection moves the date accrued to",
       context do
    person = context.person
    full_time(person)
    annual = leave_type(context, %{})
    entitlement(context, annual, %{grant_amount: "200"})

    [whole_year] = Ledger.statements(person, ~D[2025-03-03])

    [projected] =
      Ledger.statements(person, ~D[2025-03-03], [day(annual, ~D[2025-03-01], "8", :hours)])

    # Dated past the date asked about, so the account has to run on to it to answer at all.
    ahead = [day(annual, ~D[2025-03-03], "8", :hours)]

    assert {:ok, projected_ahead} =
             Ledger.fetch_statement(person, annual.id, ~D[2025-02-28], ahead)

    # Approved for three months' time, so it is spent out of the year that has been accrued and
    # accrues nothing further.
    take(person, annual, ~D[2025-06-02], "8", :hours)

    assert Decimal.equal?(whole_year.balance, "200.00")
    assert Decimal.equal?(projected.balance, "192.00")
    assert Decimal.equal?(projected_ahead.balance, "192.00")
    assert Decimal.equal?(statement(person, annual, ~D[2025-03-03]).balance, "192.00")
  end

  test "entitlement is not worked out where the hours are unknown", context do
    person = context.person
    weekdays(person, ~D[2024-04-01], "8")
    annual = leave_type(context, %{})
    entitlement(context, annual, %{grant_amount: "200"})

    assert_raise RuntimeError, ~r/no work pattern in force on 2024-03-04/, fn ->
      Ledger.statements(person, ~D[2025-03-03])
    end
  end

  test "an accrual of nothing is not a movement", context do
    person = context.person
    weekdays(person, @started, "0")
    annual = leave_type(context, %{})
    entitlement(context, annual, %{grant_amount: "200"})

    statement = statement(person, annual, ~D[2025-03-03])

    assert movements(statement) == []
    assert Decimal.equal?(statement.balance, "0.00")
  end

  test "the cap that trims a period end is the one in force at it", context do
    person = context.person
    full_time(person)
    sick = leave_type(context, %{name: "Sick leave", unit: :days, position: 2})

    capped = %{
      grant_amount: "20",
      grant_timing: :period_start,
      pro_rated_by_fte: false,
      expiry_rule: :cap
    }

    # The organisation tightens the cap part-way through, so each entitlement governs the period
    # ends it covers and no others.
    entitlement(
      context,
      sick,
      Map.merge(capped, %{rollover_cap: "40", effective_to: ~D[2025-06-30]})
    )

    entitlement(
      context,
      sick,
      Map.merge(capped, %{rollover_cap: "5", effective_from: ~D[2025-07-01]})
    )

    Fixtures.balance_entry(%{person_id: person.id, leave_type_id: sick.id, amount: "30"})

    statement = statement(person, sick, ~D[2026-03-03])

    assert movements(statement) == [
             {:opening_balance, ~D[2024-01-01], Decimal.new("30.00"), nil},
             {:grant, @started, Decimal.new("20.00"), ~D[2025-06-30]},
             {:rollover_cap, ~D[2025-03-03], Decimal.new("-10.00"), nil},
             {:grant, ~D[2025-03-04], Decimal.new("20.00"), ~D[2025-06-30]},
             {:expiry, ~D[2025-06-30], Decimal.new("-20.00"), nil},
             {:expiry, ~D[2025-06-30], Decimal.new("-20.00"), nil},
             {:rollover_cap, ~D[2026-03-03], Decimal.new("-15.00"), nil}
           ]

    assert Decimal.equal?(statement.balance, "5.00")
  end

  test "the cap keeps falling due after granting has stopped", context do
    person = context.person
    full_time(person)
    sick = leave_type(context, %{name: "Sick leave", unit: :days, position: 2})

    entitlement(context, sick, %{
      grant_amount: "20",
      grant_timing: :period_start,
      pro_rated_by_fte: false,
      expiry_rule: :cap,
      rollover_cap: "5",
      granted_to: ~D[2025-03-03]
    })

    Fixtures.balance_entry(%{
      person_id: person.id,
      leave_type_id: sick.id,
      date: ~D[2025-06-01],
      kind: :adjustment,
      amount: "30",
      reason: "Imported from the old spreadsheet"
    })

    statement = statement(person, sick, ~D[2026-03-04])

    assert movements(statement) == [
             {:grant, @started, Decimal.new("20.00"), nil},
             {:rollover_cap, ~D[2025-03-03], Decimal.new("-15.00"), nil},
             {:adjustment, ~D[2025-06-01], Decimal.new("30.00"), nil},
             {:rollover_cap, ~D[2026-03-03], Decimal.new("-30.00"), nil}
           ]

    assert Decimal.equal?(statement.balance, "5.00")
  end

  test "correcting an FTE that was wrong all year re-works the balance", context do
    person = context.person
    pattern = full_time(person)
    annual = leave_type(context, %{})
    entitlement(context, annual, %{grant_amount: "200"})

    assert Decimal.equal?(statement(person, annual, ~D[2025-03-03]).balance, "200.00")

    # They were on half a week the whole time, not a full one, so the year accrues half as much.
    {:ok, _corrected} =
      People.update_work_pattern(pattern, nil, %{
        monday_hours: "4",
        tuesday_hours: "4",
        wednesday_hours: "4",
        thursday_hours: "4",
        friday_hours: "4"
      })

    assert Decimal.equal?(statement(person, annual, ~D[2025-03-03]).balance, "100.00")
  end

  test "correcting an employment start date moves every anniversary hanging off it", context do
    person = context.person
    full_time(person)
    longevity = leave_type(context, %{name: "Longevity leave", unit: :days, position: 2})

    entitlement(context, longevity, %{
      grant_amount: "1",
      grant_timing: :period_start,
      pro_rated_by_fte: false,
      expiry_rule: :grant_period_end
    })

    assert movements(statement(person, longevity, ~D[2025-03-31])) == [
             {:grant, @started, Decimal.new("1.00"), ~D[2025-03-03]},
             {:expiry, ~D[2025-03-03], Decimal.new("-1.00"), nil},
             {:grant, ~D[2025-03-04], Decimal.new("1.00"), ~D[2026-03-03]}
           ]

    {:ok, corrected} = People.update_person(person, nil, %{employment_start_date: ~D[2024-06-01]})

    assert movements(statement(corrected, longevity, ~D[2025-03-31])) == [
             {:grant, ~D[2024-06-01], Decimal.new("1.00"), ~D[2025-05-31]}
           ]
  end

  test "an account appears for each leave type the person holds one in", context do
    person = context.person
    full_time(person)
    annual = leave_type(context, %{})
    carried = leave_type(context, %{name: "Carried leave", position: 2})
    unused = leave_type(context, %{name: "Study leave", position: 3})
    entitlement(context, annual, %{grant_amount: "200"})

    Fixtures.balance_entry(%{person_id: person.id, leave_type_id: carried.id, amount: "40"})

    statements = Ledger.statements(person, ~D[2024-06-01])

    assert Enum.map(statements, & &1.leave_type.name) == ["Annual leave", "Carried leave"]
    assert Ledger.fetch_statement(person, unused.id, ~D[2024-06-01]) == :error
  end
end
