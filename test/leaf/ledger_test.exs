defmodule Leaf.LedgerTest do
  use Leaf.DataCase, async: true

  alias Leaf.Fixtures
  alias Leaf.Leave
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
    calendar = Fixtures.calendar(%{organisation_id: context.organisation.id})

    Enum.each(dates, &Fixtures.public_holiday(%{calendar_id: calendar.id, date: &1}))

    Fixtures.calendar_assignment(%{
      person_id: person.id,
      calendar_id: calendar.id,
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
    person |> Ledger.statements(as_at) |> Enum.find(&(&1.leave_type.id == leave_type.id))
  end

  defp movements(statement) do
    Enum.map(statement.movements, &{&1.kind, &1.date, Decimal.round(&1.amount, 2), &1.expires_on})
  end

  defp lots(statement) do
    Enum.map(statement.lots, &{Decimal.round(&1.amount, 2), &1.expires_on})
  end

  defp drawn(statement), do: Enum.filter(statement.movements, &(&1.kind == :taken))

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

  test "a day worth no hours draws nothing rather than refusing to be counted", context do
    person = context.person
    full_time(person)
    sick = leave_type(context, %{name: "Sick leave", unit: :days, position: 2})

    entitlement(context, sick, %{
      grant_amount: "10",
      grant_timing: :period_start,
      pro_rated_by_fte: false
    })

    take(person, sick, ~D[2024-05-01], "4.5", :hours)

    # The Wednesday those hours were filed on is corrected to a day the person does not work.
    Fixtures.work_pattern(%{
      person_id: person.id,
      effective_from: ~D[2024-04-01],
      wednesday_hours: "0"
    })

    assert Decimal.equal?(statement(person, sick, ~D[2024-05-31]).balance, "10.00")
  end

  test "a public holiday added over booked leave deducts nothing for it", context do
    person = context.person
    full_time(person)
    annual = leave_type(context, %{})
    entitlement(context, annual, %{grant_amount: "200"})

    take(person, annual, ~D[2024-05-01], "1", :days)
    take(person, annual, ~D[2024-05-02], "8", :hours)

    # The days are granted off after the fact, so they stopped being days off anybody spent.
    observes(context, person, [~D[2024-05-01], ~D[2024-05-02]])

    assert [in_days, in_hours] = drawn(statement(person, annual, ~D[2024-05-31]))
    assert Decimal.equal?(in_days.amount, 0)
    assert Decimal.equal?(in_hours.amount, 0)
  end

  test "converting a day rounds once, where the figure is shown", context do
    person = context.person
    weekdays(person, @started, "9")
    sick = leave_type(context, %{name: "Sick leave", unit: :days, position: 2})

    entitlement(context, sick, %{
      grant_amount: "10",
      grant_timing: :period_start,
      pro_rated_by_fte: false
    })

    # An hour off on each of eight nine-hour days: eight ninths of a day, not eight elevenths.
    Enum.each(
      [
        ~D[2024-05-01],
        ~D[2024-05-02],
        ~D[2024-05-03],
        ~D[2024-05-06],
        ~D[2024-05-07],
        ~D[2024-05-08],
        ~D[2024-05-09],
        ~D[2024-05-10]
      ],
      &take(person, sick, &1, "1", :hours)
    )

    statement = statement(person, sick, ~D[2024-05-31])
    taken = Enum.reduce(drawn(statement), Decimal.new(0), &Decimal.add(&2, &1.amount))

    assert Decimal.equal?(Decimal.round(taken, 4), "-0.8889")
    assert Decimal.equal?(statement.balance, "9.11")
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

    # Still held on the day it lapses, since it can still be drawn on that day.
    on_lapse = statement(person, carried, ~D[2024-06-30])
    after_lapse = statement(person, carried, ~D[2024-07-01])

    assert lots(on_lapse) == [
             {Decimal.new("2.00"), ~D[2024-06-30]},
             {Decimal.new("40.00"), nil}
           ]

    assert Decimal.equal?(on_lapse.balance, "42.00")

    assert List.last(movements(after_lapse)) ==
             {:expiry, ~D[2024-06-30], Decimal.new("-2.00"), nil}

    assert Decimal.equal?(after_lapse.balance, "40.00")
  end

  test "leave approved for later is spent already, out of the lots still live when it is taken",
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

    # Read in May, the June top-up has not lapsed and so is still held, but it cannot pay for
    # August: the whole 10 hours is what is about to lapse, and the never-lapsing lot is what goes.
    assert lots(statement) == [
             {Decimal.new("10.00"), ~D[2024-06-30]},
             {Decimal.new("32.00"), nil}
           ]

    assert Decimal.equal?(statement.balance, "42.00")
  end

  test "leave draws on what an accrual has earned by its date, and no more", context do
    person = context.person
    full_time(person)
    quarterly = leave_type(context, %{name: "Quarterly leave", position: 2})

    entitlement(context, quarterly, %{
      grant_amount: "8",
      grant_basis: :calendar_year,
      grant_period: :quarter,
      expiry_rule: :grant_period_end
    })

    Fixtures.balance_entry(%{
      person_id: person.id,
      leave_type_id: quarterly.id,
      date: ~D[2024-04-01],
      kind: :adjustment,
      amount: "5",
      reason: "Carried over by agreement"
    })

    take(person, quarterly, ~D[2024-05-15], "4", :hours)

    # 45 of the quarter's 91 days have accrued 3.96 by the 15th, which lapses at the quarter's end
    # and so is spent first. Only the 0.04 left over comes out of the 5 that never lapse.
    expected = [{Decimal.new("0.09"), ~D[2024-09-30]}, {Decimal.new("4.96"), nil}]
    statement = statement(person, quarterly, ~D[2024-07-01])

    assert lots(statement) == expected
    assert Decimal.equal?(statement.balance, "5.04")

    # The same hours recorded afresh from May split the quarter's accrual without changing it.
    weekdays(person, ~D[2024-05-01], "8")
    statement = statement(person, quarterly, ~D[2024-07-01])

    assert lots(statement) == expected
    assert Decimal.equal?(statement.balance, "5.04")

    # Nor does June spent on unpaid leave reach back to what had accrued by the 15th of May.
    unpaid = leave_type(context, %{name: "Unpaid leave", position: 3, suspends_accrual: true})

    Fixtures.leave_request(%{
      person_id: person.id,
      days:
        for(
          date <- Date.range(~D[2024-06-03], ~D[2024-06-28]),
          Date.day_of_week(date) < 6,
          do: %{leave_type_id: unpaid.id, date: date, amount: "1", unit: :days}
        )
    })

    assert lots(statement(person, quarterly, ~D[2024-07-01])) == expected
  end

  test "taking leave out of an accrual does not bring its lapse forward", context do
    person = context.person
    full_time(person)
    quarterly = leave_type(context, %{name: "Quarterly leave", position: 2})

    entitlement(context, quarterly, %{
      grant_amount: "8",
      grant_basis: :calendar_year,
      grant_period: :quarter,
      expiry_rule: :window,
      expiry_window_days: 20
    })

    take(person, quarterly, ~D[2024-04-10], "1", :hours)

    # The hour comes out of March's accrual, lapsing on the 20th of April. April to June's accrual
    # lapses 20 days after June, the part cut off on the 10th included.
    statement = statement(person, quarterly, ~D[2024-06-30])

    assert lots(statement) == [
             {Decimal.new("7.12"), ~D[2024-07-20]},
             {Decimal.new("0.88"), ~D[2024-07-20]}
           ]

    assert Decimal.equal?(statement.balance, "8.00")
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

    statement = statement(person, sick, ~D[2026-03-04])

    assert movements(statement) == [
             {:grant, @started, Decimal.new("20.00"), nil},
             {:taken, ~D[2024-05-01], Decimal.new("-1.00"), nil},
             {:grant, ~D[2025-03-04], Decimal.new("20.00"), nil},
             {:adjustment, ~D[2025-06-01], Decimal.new("5.00"), ~D[2026-06-30]},
             {:rollover_cap, ~D[2026-03-03], Decimal.new("-19.00"), nil},
             {:grant, ~D[2026-03-04], Decimal.new("20.00"), nil}
           ]

    assert lots(statement) == [
             {Decimal.new("5.00"), ~D[2026-06-30]},
             {Decimal.new("20.00"), nil},
             {Decimal.new("20.00"), nil}
           ]

    assert Decimal.equal?(statement.balance, "45.00")
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

    unlapsed = statement(person, birthday, ~D[2024-08-24])
    lapsed = statement(person, birthday, ~D[2024-08-25])

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

    assert statement(without_birth_date, birthday, ~D[2024-08-23]) == nil
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

  test "a public holiday allowance credits only the holidays a leaver is there for", context do
    person =
      Fixtures.person(%{
        organisation_id: context.organisation.id,
        employment_end_date: ~D[2024-05-01]
      })

    part_time(person)

    Fixtures.policy_assignment(%{
      person_id: person.id,
      leave_policy_id: context.policy.id,
      effective_from: @started
    })

    allowance = leave_type(context, %{name: "Public holiday allowance", position: 2})

    entitlement(context, allowance, %{
      amount_source: :public_holidays,
      grant_amount: nil,
      grant_timing: :period_start
    })

    observes(context, person, [~D[2024-04-25], ~D[2024-12-25], ~D[2025-01-01]])

    # One of the leave year's three holidays falls before they left; the rest are none of theirs.
    assert movements(statement(person, allowance, ~D[2024-06-30])) ==
             [{:grant, @started, Decimal.new("7.20"), nil}]
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

    calendar = Fixtures.calendar(%{organisation_id: context.organisation.id})
    Fixtures.public_holiday(%{calendar_id: calendar.id, date: ~D[2024-12-25]})

    Fixtures.calendar_assignment(%{
      person_id: person.id,
      calendar_id: calendar.id,
      effective_from: ~D[2024-06-01]
    })

    assert_raise RuntimeError, ~r/no calendar in force on 2024-03-04/, fn ->
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

  test "a projection is only the leave types the days draw on that hold a balance", context do
    person = context.person
    full_time(person)
    annual = leave_type(context, %{})
    unpaid = leave_type(context, %{name: "Unpaid leave", position: 2})
    study = leave_type(context, %{name: "Study leave", position: 3})

    nothing = %{
      amount_source: :none,
      grant_amount: nil,
      grant_basis: nil,
      grant_period: nil,
      grant_timing: nil
    }

    entitlement(context, annual, %{})
    entitlement(context, unpaid, nothing)
    entitlement(context, study, nothing)
    take(person, study, ~D[2024-05-01], "8", :hours)

    days = [day(annual, ~D[2024-05-02], "8", :hours), day(unpaid, ~D[2024-05-03], "8", :hours)]

    assert [statement] = Ledger.projected(person, days)
    assert statement.leave_type.id == annual.id
  end

  test "balances leave out a type never granted anything, whichever date they are read at",
       context do
    person = context.person
    full_time(person)
    annual = leave_type(context, %{})
    study = leave_type(context, %{name: "Study leave", position: 2})
    bereavement = leave_type(context, %{name: "Bereavement leave", position: 3})

    entitlement(context, annual, %{})
    take(person, study, ~D[2024-07-01], "8", :hours)
    take(person, bereavement, ~D[2024-07-01], "8", :hours)

    Fixtures.balance_entry(%{
      person_id: person.id,
      leave_type_id: bereavement.id,
      date: ~D[2024-07-10],
      kind: :adjustment,
      amount: "8",
      reason: "Granted for a funeral"
    })

    Fixtures.balance_entry(%{person_id: person.id, leave_type_id: study.id, date: @started})

    Fixtures.balance_entry(%{
      person_id: person.id,
      leave_type_id: study.id,
      date: ~D[2024-07-10],
      kind: :adjustment,
      amount: "-8",
      reason: "Corrected"
    })

    assert Ledger.granted(person) == MapSet.new([annual.id, bereavement.id])

    assert person |> Ledger.balances(~D[2024-07-05]) |> Enum.map(& &1.leave_type.id) ==
             [annual.id, bereavement.id]
  end

  test "a type is granted by a policy only where it grants while the person is on it", context do
    study = leave_type(context, %{name: "Study leave"})
    sabbatical = leave_type(context, %{name: "Sabbatical", position: 2})

    stops = %{
      amount_source: :none,
      grant_amount: nil,
      grant_basis: nil,
      grant_period: nil,
      grant_timing: nil
    }

    entitlement(context, study, %{effective_from: ~D[2023-01-01], effective_to: ~D[2023-12-31]})
    entitlement(context, study, Map.put(stops, :effective_from, ~D[2024-01-01]))
    entitlement(context, sabbatical, %{effective_to: ~D[2024-06-30]})
    entitlement(context, sabbatical, Map.put(stops, :effective_from, ~D[2024-07-01]))

    assert Ledger.granted(context.person) == MapSet.new([sabbatical.id])
  end

  test "leave that suspends accrual takes its share of working time off accrual, not a block",
       context do
    person = context.person
    full_time(person)
    annual = leave_type(context, %{})
    sick = leave_type(context, %{name: "Sick leave", unit: :days, position: 2})
    unpaid = leave_type(context, %{name: "Unpaid leave", position: 3, suspends_accrual: true})
    entitlement(context, annual, %{grant_amount: "365"})

    entitlement(context, sick, %{
      grant_amount: "10",
      grant_timing: :period_start,
      pro_rated_by_fte: false
    })

    # Two whole weeks and half the Monday after are 84 of four weeks' 160 hours, so the 28 hours
    # four weeks of a 365-hour year accrue keep 76/160 of themselves.
    weeks =
      for date <- Date.range(~D[2024-03-04], ~D[2024-03-15]), Date.day_of_week(date) < 6, do: date

    Fixtures.leave_request(%{
      person_id: person.id,
      days:
        Enum.map(weeks, &%{leave_type_id: unpaid.id, date: &1, amount: "1", unit: :days}) ++
          [%{leave_type_id: unpaid.id, date: ~D[2024-03-18], amount: "4", unit: :hours}]
    })

    assert movements(statement(person, annual, ~D[2024-03-31])) ==
             [{:accrual, ~D[2024-03-31], Decimal.new("13.30"), nil}]

    assert Decimal.equal?(statement(person, sick, ~D[2024-03-31]).balance, "10.00")
  end

  test "leave that does not suspend accrual, or no longer does, takes nothing off it", context do
    person = context.person
    full_time(person)
    annual = leave_type(context, %{})
    bereavement = leave_type(context, %{name: "Bereavement leave", unit: :days, position: 2})
    unpaid = leave_type(context, %{name: "Unpaid leave", position: 3, suspends_accrual: true})
    entitlement(context, annual, %{grant_amount: "365"})
    admin = Fixtures.person(%{organisation_id: context.organisation.id, role: :admin})

    take(person, bereavement, ~D[2024-03-11], "1", :days)
    unpaid_day = take(person, unpaid, ~D[2024-03-12], "1", :days)

    # 28 hours accrued over four weeks, less the 8 of their 160 that were suspended.
    assert Decimal.equal?(statement(person, annual, ~D[2024-03-31]).balance, "26.60")

    {:ok, request} = Leave.fetch_request(unpaid_day.id)
    {:ok, _cancelled} = Leave.cancel(request, admin)

    assert Decimal.equal?(statement(person, annual, ~D[2024-03-31]).balance, "28.00")
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

    wound_down = statement(person, quarterly, ~D[2025-03-31])
    ended = statement(person, quarterly, ~D[2025-04-01])

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

  test "a balance entered by hand lapses with the entitlement it is held under", context do
    person = context.person
    full_time(person)
    quarterly = leave_type(context, %{name: "Quarterly leave", position: 2})

    quarterly_terms = %{
      grant_amount: "8",
      grant_basis: :calendar_year,
      grant_period: :quarter,
      grant_timing: :period_start,
      pro_rated_by_fte: false
    }

    # The old terms stop granting at the end of June and are spendable to the end of September; the
    # new ones take over from July, so the two overlap over the quarter between.
    entitlement(
      context,
      quarterly,
      Map.merge(quarterly_terms, %{granted_to: ~D[2024-06-30], effective_to: ~D[2024-09-30]})
    )

    entitlement(context, quarterly, Map.put(quarterly_terms, :effective_from, ~D[2024-07-01]))

    entry = %{person_id: person.id, leave_type_id: quarterly.id}
    adjusted = %{kind: :adjustment, amount: "5", reason: "Carried over by agreement"}

    # Brought in before the old terms reached them, adjusted under them, and adjusted while both are
    # in force: none of them says it lapses.
    Fixtures.balance_entry(Map.put(entry, :amount, "30"))
    Fixtures.balance_entry(entry |> Map.merge(adjusted) |> Map.put(:date, ~D[2024-05-01]))
    Fixtures.balance_entry(entry |> Map.merge(adjusted) |> Map.put(:date, ~D[2024-08-01]))

    statement = statement(person, quarterly, ~D[2024-10-01])
    movements = movements(statement)

    assert {:opening_balance, ~D[2024-01-01], Decimal.new("30.00"), ~D[2024-09-30]} in movements
    assert {:adjustment, ~D[2024-05-01], Decimal.new("5.00"), ~D[2024-09-30]} in movements
    assert {:adjustment, ~D[2024-08-01], Decimal.new("5.00"), nil} in movements

    # The new terms' July and October grants, and the adjustment held under them.
    assert Decimal.equal?(statement.balance, "21.00")

    # The page listing entries reads the same lapse dates, while each entry keeps its own.
    assert [{%{expires_on: nil}, ~D[2024-09-30]}, {_may, ~D[2024-09-30]}, {_august, nil}] =
             Ledger.balance_entries(person)
  end

  test "raising what an entitlement grants keeps what it has already granted", context do
    person = context.person
    full_time(person)
    annual = leave_type(context, %{})

    # A raise from 200 to 220 hours part-way through the second year. The old row stops granting on
    # the 15th and the new one opens on the 16th; the old row's life runs on, so nothing lapses and
    # the year splits 73 days to 292.
    entitlement(context, annual, %{grant_amount: "200", granted_to: ~D[2025-05-15]})
    entitlement(context, annual, %{grant_amount: "220", effective_from: ~D[2025-05-16]})

    statement = statement(person, annual, ~D[2026-03-03])

    assert movements(statement) == [
             {:accrual, ~D[2025-03-03], Decimal.new("200.00"), nil},
             {:accrual, ~D[2025-05-15], Decimal.new("40.00"), nil},
             {:accrual, ~D[2026-03-03], Decimal.new("176.00"), nil}
           ]

    assert Decimal.equal?(statement.balance, "416.00")
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
      grant_timing: nil
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
      Ledger.statements(person, ~D[2025-03-03], [day(annual, ~D[2025-02-28], "8", :hours)])

    # Dated past the date asked about, so the account has to run on to it to answer at all.
    ahead = [day(annual, ~D[2025-03-03], "8", :hours)]

    [projected_ahead] = Ledger.statements(person, ~D[2025-02-28], ahead)

    # Approved for three months' time, so it is spent out of the year that has been accrued and
    # accrues nothing further.
    take(person, annual, ~D[2025-06-02], "8", :hours)

    assert Decimal.equal?(whole_year.balance, "200.00")
    assert Decimal.equal?(projected.balance, "192.00")
    assert Decimal.equal?(projected_ahead.balance, "192.00")
    assert Decimal.equal?(statement(person, annual, ~D[2025-03-03]).balance, "192.00")
  end

  test "nothing is worked out where the hours are unknown", context do
    person = context.person
    weekdays(person, ~D[2024-04-01], "8")
    annual = leave_type(context, %{})
    entitlement(context, annual, %{grant_amount: "200"})

    Fixtures.leave_request(%{
      person_id: person.id,
      status: :pending,
      days: [%{leave_type_id: annual.id, date: ~D[2024-05-06], amount: "8", unit: :hours}]
    })

    refute Ledger.ready?(person, ~D[2025-03-03])
    assert Ledger.statements(person, ~D[2025-03-03]) == []
    assert Ledger.awaiting(person) == %{}
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

    # The organisation tightens the cap part-way through the second year, so each entitlement
    # governs the period ends it covers and no others. The handover is mid-period, so both rows
    # reach its end and the cap that falls due is the one still granting there.
    entitlement(
      context,
      sick,
      Map.merge(capped, %{rollover_cap: "40", granted_to: ~D[2025-06-30]})
    )

    entitlement(
      context,
      sick,
      Map.merge(capped, %{rollover_cap: "5", effective_from: ~D[2025-07-01]})
    )

    Fixtures.balance_entry(%{person_id: person.id, leave_type_id: sick.id, amount: "30"})

    statement = statement(person, sick, ~D[2026-03-04])

    assert movements(statement) == [
             {:opening_balance, ~D[2024-01-01], Decimal.new("30.00"), nil},
             {:grant, @started, Decimal.new("20.00"), nil},
             {:rollover_cap, ~D[2025-03-03], Decimal.new("-10.00"), nil},
             {:grant, ~D[2025-03-04], Decimal.new("20.00"), nil},
             {:rollover_cap, ~D[2026-03-03], Decimal.new("-55.00"), nil},
             {:grant, ~D[2026-03-04], Decimal.new("20.00"), nil}
           ]

    assert Decimal.equal?(statement.balance, "25.00")
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
    leave_type(context, %{name: "Study leave", position: 3})
    entitlement(context, annual, %{grant_amount: "200"})

    Fixtures.balance_entry(%{person_id: person.id, leave_type_id: carried.id, amount: "40"})

    statements = Ledger.statements(person, ~D[2024-06-01])

    assert Enum.map(statements, & &1.leave_type.name) == ["Annual leave", "Carried leave"]
  end
end
