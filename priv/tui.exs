# Throwaway interactive harness for driving Leaf's contexts by hand.
#
#     mix run priv/tui.exs
#
# Not production code, not tested, not tidy. Lists come straight off the Repo where no context
# function exists yet; every write and every calculation goes through the contexts.

Logger.configure(level: :warning)

defmodule Tui do
  import Ecto.Query

  alias Leaf.Audit.Entry
  alias Leaf.Leave
  alias Leaf.Leave.Request
  alias Leaf.Ledger
  alias Leaf.Org
  alias Leaf.Org.Calendar
  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.People.PersonCalendar
  alias Leaf.People.PersonPolicyAssignment
  alias Leaf.People.WorkPattern
  alias Leaf.Policies
  alias Leaf.Policies.LeavePolicy
  alias Leaf.Policies.LeaveType
  alias Leaf.Repo
  alias Leaf.Seed

  @days_of_week [
    :monday_hours,
    :tuesday_hours,
    :wednesday_hours,
    :thursday_hours,
    :friday_hours,
    :saturday_hours,
    :sunday_hours
  ]

  def run do
    case Org.organisations() do
      [] -> seed_or_quit()
      [org | _rest] -> start(org)
    end
  end

  defp seed_or_quit do
    IO.puts("No organisation in the database.")

    case ask("Seed the example organisation? (y/n)") do
      "y" ->
        {:ok, %{organisation: org}} = Seed.run()
        IO.puts("Seeded #{org.name}.")
        start(org)

      _ ->
        IO.puts("Nothing to do. Run mix leaf.seed first.")
    end
  end

  defp start(org) do
    actor = choose_person(org, "Act as whom?") || nil
    menu(%{org: org, actor: actor, as_at: Date.utc_today()})
  end

  # ── main menu ───────────────────────────────────────────────────────────────

  defp menu(state) do
    IO.puts("""

    ══ #{state.org.name} ═════════════════════════════════════════════
     acting as #{who(state.actor)}   ·   as at #{state.as_at}

      1  Change actor          5  Balance entries
      2  Change 'as at' date   6  Organisation & policies
      3  People                7  Audit log
      4  Balances & leave
      q  Quit\
    """)

    case ask("Choose") do
      "q" -> :ok
      "1" -> menu(%{state | actor: choose_person(state.org, "Act as whom?") || state.actor})
      "2" -> menu(%{state | as_at: ask_date("As at", state.as_at)})
      "3" -> section(state, &people_menu/1)
      "4" -> section(state, &leave_menu/1)
      "5" -> section(state, &entries_menu/1)
      "6" -> section(state, &org_menu/1)
      "7" -> section(state, &audit/1)
      _ -> menu(state)
    end
  end

  # ── people ──────────────────────────────────────────────────────────────────

  defp people_menu(state) do
    IO.puts("""

    ── People ──
      1  List people             4  Add work pattern
      2  Show person             5  Assign leave policy
      3  Create person           6  Assign holiday calendar
      blank  back\
    """)

    case ask("Choose") do
      "" -> :ok
      "1" -> again(state, &people_menu/1, &list_people/1)
      "2" -> again(state, &people_menu/1, &show_person/1)
      "3" -> again(state, &people_menu/1, &create_person/1)
      "4" -> again(state, &people_menu/1, &add_work_pattern/1)
      "5" -> again(state, &people_menu/1, &assign_policy/1)
      "6" -> again(state, &people_menu/1, &assign_calendar/1)
      _ -> people_menu(state)
    end
  end

  defp list_people(state) do
    people = people(state.org)
    names = Map.new(people, &{&1.id, &1.name})

    IO.puts("")

    Enum.each(people, fn person ->
      IO.puts(
        "  #{pad(person.name, 20)} #{pad(person.email, 26)} #{pad(to_string(person.role), 7)}" <>
          " from #{person.employment_start_date}" <>
          ending(person) <>
          manager(person, names)
      )
    end)
  end

  defp ending(%{employment_end_date: nil}), do: ""
  defp ending(person), do: " to #{person.employment_end_date}"

  defp manager(%{manager_id: nil}, _names), do: ""
  defp manager(person, names), do: "  manager: #{names[person.manager_id]}"

  defp show_person(state) do
    with %Person{} = person <- choose_person(state.org, "Which person?") do
      IO.puts("""

        #{person.name} <#{person.email}>  ·  #{person.role}
        employment #{person.employment_start_date}#{ending(person)}  ·  born #{person.birth_date}
      """)

      print_pattern_on(state, person)
      print_rows("Work patterns", succession(person, WorkPattern), &describe_pattern/1)
      print_rows("Policies", succession(person, PersonPolicyAssignment), &describe_assignment/1)
      print_rows("Calendars", succession(person, PersonCalendar), &describe_assignment/1)
    end
  end

  defp print_pattern_on(state, person) do
    case People.fetch_work_pattern_on(person, state.as_at) do
      {:ok, pattern} ->
        weekly = People.weekly_hours(pattern)
        fte = People.fte(pattern, state.org.full_time_week_hours)
        IO.puts("  On #{state.as_at}: #{num(weekly)}h a week (#{num(fte)} FTE)")

      :error ->
        IO.puts("  On #{state.as_at}: no work pattern on record")
    end
  end

  defp print_rows(label, rows, describe) do
    IO.puts("\n  #{label}:")

    case rows do
      [] ->
        IO.puts("    (none)")

      rows ->
        Enum.each(
          Enum.sort_by(rows, & &1.effective_from, Date),
          &IO.puts("    " <> describe.(&1))
        )
    end
  end

  defp describe_pattern(pattern) do
    hours = Enum.map_join(@days_of_week, ",", &num(Map.fetch!(pattern, &1)))

    "from #{pattern.effective_from}  #{hours}  (#{num(People.weekly_hours(pattern))}h)"
  end

  defp describe_assignment(%PersonPolicyAssignment{} = assignment) do
    "from #{assignment.effective_from}  #{policy_name(assignment.leave_policy_id)}"
  end

  defp describe_assignment(%PersonCalendar{} = assignment) do
    "from #{assignment.effective_from}  #{calendar_name(assignment.calendar_id)}"
  end

  defp create_person(state) do
    attrs = %{
      name: ask("Name"),
      email: ask("Email"),
      role: ask_choice("Role", [:member, :admin]),
      employment_start_date: ask_date("Employment start", state.as_at),
      birth_date: ask_date("Birth date", ~D[1990-01-01]),
      manager_id: id_of(choose_person(state.org, "Manager (blank for none)"))
    }

    report(People.create_person(state.org, state.actor, attrs), & &1.name)
    IO.puts("  Now give them a work pattern, a policy and a calendar.")
  end

  defp add_work_pattern(state) do
    with %Person{} = person <- choose_person(state.org, "Whose pattern?") do
      from = ask_date("Effective from", person.employment_start_date)
      hours = ask_hours()

      report(
        People.create_work_pattern(person, state.actor, Map.put(hours, :effective_from, from))
      )
    end
  end

  defp ask_hours do
    entered =
      "Hours Mon,Tue,Wed,Thu,Fri,Sat,Sun"
      |> ask_default("8,8,8,8,8,0,0")
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    Map.new(Enum.zip(@days_of_week, entered))
  end

  defp assign_policy(state) do
    with %Person{} = person <- choose_person(state.org, "Whose policy?"),
         %LeavePolicy{} = policy <- choose_policy(state) do
      from = ask_date("Effective from", person.employment_start_date)

      report(
        People.create_policy_assignment(person, state.actor, %{
          leave_policy_id: policy.id,
          effective_from: from
        })
      )
    end
  end

  defp assign_calendar(state) do
    with %Person{} = person <- choose_person(state.org, "Whose calendar?"),
         %Calendar{} = calendar <- choose_calendar(state) do
      from = ask_date("Effective from", person.employment_start_date)

      report(
        People.create_calendar_assignment(person, state.actor, %{
          calendar_id: calendar.id,
          effective_from: from
        })
      )
    end
  end

  # ── balances & leave ────────────────────────────────────────────────────────

  defp leave_menu(state) do
    IO.puts("""

    ── Balances & leave ──
      1  Balances as at #{state.as_at}     6  Approve a request
      2  One leave type in full        7  Decline a request
      3  Working days in a range       8  Cancel a request
      4  List requests                 9  Amend a request
      5  File a request                0  Days taken
      blank  back\
    """)

    case ask("Choose") do
      "" -> :ok
      "1" -> again(state, &leave_menu/1, &balances/1)
      "2" -> again(state, &leave_menu/1, &one_balance/1)
      "3" -> again(state, &leave_menu/1, &working_days/1)
      "4" -> again(state, &leave_menu/1, &list_requests/1)
      "5" -> again(state, &leave_menu/1, &file_request/1)
      "6" -> again(state, &leave_menu/1, &approve/1)
      "7" -> again(state, &leave_menu/1, &decline/1)
      "8" -> again(state, &leave_menu/1, &cancel/1)
      "9" -> again(state, &leave_menu/1, &amend/1)
      "0" -> again(state, &leave_menu/1, &days_taken/1)
      _ -> leave_menu(state)
    end
  end

  defp balances(state) do
    with %Person{} = person <- choose_person(state.org, "Whose balances?") do
      case Ledger.statements(person, state.as_at) do
        [] -> IO.puts("\n  Holds nothing.")
        statements -> Enum.each(statements, &print_statement(&1, :summary))
      end
    end
  end

  defp one_balance(state) do
    with %Person{} = person <- choose_person(state.org, "Whose balance?"),
         statements = Ledger.statements(person, state.as_at),
         %{} = statement <- choose(Enum.map(statements, &{&1.leave_type.name, &1}), "Which type?") do
      print_statement(statement, :full)
    end
  end

  defp print_statement(statement, detail) do
    IO.puts("""

      #{statement.leave_type.name} (#{statement.leave_type.unit})  ·  balance #{num(statement.balance)}\
    """)

    IO.puts("    lots held:")

    case statement.lots do
      [] ->
        IO.puts("      (none)")

      lots ->
        Enum.each(lots, &IO.puts("      #{pad(num(&1.amount), 10)} #{lapses(&1.expires_on)}"))
    end

    print_movements(statement.movements, detail)
  end

  defp print_movements(movements, :summary) do
    IO.puts("    movements by kind:")

    movements
    |> Enum.group_by(& &1.kind)
    |> Enum.each(fn {kind, group} ->
      IO.puts(
        "      #{pad(to_string(kind), 16)} #{pad(num(total(group)), 10)} (#{length(group)})"
      )
    end)
  end

  defp print_movements(movements, :full) do
    IO.puts("    movements (#{length(movements)}):")

    Enum.each(movements, fn movement ->
      IO.puts(
        "      #{movement.date}  #{pad(to_string(movement.kind), 16)}" <>
          " #{pad(num(movement.amount), 10)} #{until(movement.expires_on)}"
      )
    end)
  end

  defp total(movements), do: Enum.reduce(movements, Decimal.new(0), &Decimal.add(&2, &1.amount))

  defp until(nil), do: ""
  defp until(date), do: "lapses #{date}"

  defp lapses(nil), do: "never lapses"
  defp lapses(date), do: "lapses #{date}"

  defp working_days(state) do
    with %Person{} = person <- choose_person(state.org, "Whose days?") do
      range = ask_range(state)
      days = Leave.working_days(person, range)

      IO.puts("\n  #{length(days)} working days:")
      Enum.each(days, fn {date, hours} -> IO.puts("    #{date}  #{num(hours)}h") end)
    end
  end

  defp list_requests(state) do
    IO.puts("")
    Enum.each(requests(state.org), &IO.puts("  " <> describe_request(&1)))
  end

  defp describe_request(request) do
    dates = Enum.map(request.days, & &1.date)

    "#{pad(request.person.name, 16)} #{pad(to_string(request.status), 10)}" <>
      " #{Enum.min(dates, Date)}..#{Enum.max(dates, Date)}" <>
      " #{length(request.days)} day(s)" <>
      " #{pad(num(total_asked(request)), 8)}" <>
      " #{short(request.id)}#{note(request)}"
  end

  defp total_asked(request) do
    Enum.reduce(request.days, Decimal.new(0), &Decimal.add(&2, &1.amount))
  end

  defp note(%{note: nil}), do: ""
  defp note(request), do: "  #{request.note}"

  defp file_request(state) do
    with %Person{} = actor <- need_actor(state),
         %Person{} = person <- choose_person(state.org, "Whose leave?"),
         %{} = days <- ask_days(state, person) do
      note = blank_to_nil(ask("Note (optional)"))

      case Leave.request(person, actor, %{days: days.entries, note: note}) do
        {:ok, request} ->
          IO.puts("  ✓ #{outcome(request)}")
          preview(person, state, days.entries)

        refused ->
          report(refused, &outcome/1)
      end
    end
  end

  defp amend(state) do
    with %Person{} = actor <- need_actor(state),
         %Request{} = request <- choose_request(state, "Which request?"),
         %{} = days <- ask_days(state, request.person) do
      note = blank_to_nil(ask("Note (optional)"))

      report(Leave.amend(request, actor, %{days: days.entries, note: note}), &outcome/1)
    end
  end

  # Returns the day entries a request will carry, built from one leave type over a date range.
  defp ask_days(state, person) do
    with %{} = leave_type <- choose_leave_type(state, "Which leave type?") do
      range = ask_range(state)

      case Leave.working_days(person, range) do
        [] ->
          IO.puts("  No working days in that range — nothing to file.")
          nil

        working ->
          IO.puts(
            "  #{length(working)} working days: #{Enum.map_join(working, ", ", &elem(&1, 0))}"
          )

          amount = ask_default("Amount per day (blank for the whole day)", "")

          %{entries: Enum.map(working, &entry(&1, leave_type, amount))}
      end
    end
  end

  defp entry({date, _hours}, leave_type, "") do
    %{leave_type_id: leave_type.id, date: date, amount: Decimal.new(1), unit: :days}
  end

  defp entry({date, _hours}, leave_type, amount) do
    %{
      leave_type_id: leave_type.id,
      date: date,
      amount: Decimal.new(amount),
      unit: leave_type.unit
    }
  end

  # What the balances would be were the request approved: the ledger takes unfiled days.
  defp preview(person, state, entries) do
    days = Enum.map(entries, &struct!(Leave.Day, &1))

    IO.puts("\n  Were it approved:")

    person
    |> Ledger.statements(state.as_at, days)
    |> Enum.each(&IO.puts("    #{pad(&1.leave_type.name, 26)} #{num(&1.balance)}"))
  end

  defp approve(state), do: decide(state, &Leave.approve(&1, &2, &3), :pending)
  defp decline(state), do: decide(state, &Leave.decline(&1, &2, &3), :pending)

  defp decide(state, fun, status) do
    with %Person{} = actor <- need_actor(state),
         %Request{} = request <- choose_request(state, "Which request?", status) do
      comment = blank_to_nil(ask("Comment (optional)"))

      report(fun.(request, actor, comment), &outcome/1)
    end
  end

  defp cancel(state) do
    with %Person{} = actor <- need_actor(state),
         %Request{} = request <- choose_request(state, "Which request?") do
      report(Leave.cancel(request, actor), &outcome/1)
    end
  end

  defp days_taken(state) do
    with %Person{} = person <- choose_person(state.org, "Whose leave?") do
      IO.puts("")

      person
      |> Leave.days_taken(state.as_at)
      |> Enum.each(fn day ->
        IO.puts(
          "  #{day.date}  #{pad(leave_type_name(day.leave_type_id), 26)} #{num(day.amount)} #{day.unit}"
        )
      end)
    end
  end

  # ── balance entries ─────────────────────────────────────────────────────────

  defp entries_menu(state) do
    IO.puts("""

    ── Balance entries ──
      1  List for a person
      2  Record an opening balance
      3  Record an adjustment
      blank  back\
    """)

    case ask("Choose") do
      "" -> :ok
      "1" -> again(state, &entries_menu/1, &list_entries/1)
      "2" -> again(state, &entries_menu/1, &create_entry(&1, :opening_balance))
      "3" -> again(state, &entries_menu/1, &create_entry(&1, :adjustment))
      _ -> entries_menu(state)
    end
  end

  defp list_entries(state) do
    with %Person{} = person <- choose_person(state.org, "Whose entries?") do
      IO.puts("")

      person
      |> Leave.balance_entries(state.as_at)
      |> Enum.each(fn entry ->
        IO.puts(
          "  #{entry.date}  #{pad(to_string(entry.kind), 16)}" <>
            " #{pad(leave_type_name(entry.leave_type_id), 26)} #{pad(num(entry.amount), 8)}" <>
            " #{lapses(entry.expires_on)}  #{entry.reason}"
        )
      end)
    end
  end

  defp create_entry(state, kind) do
    with %Person{} = actor <- need_actor(state),
         %Person{} = person <- choose_person(state.org, "Whose entry?"),
         %{} = leave_type <- choose_leave_type(state, "Which leave type?") do
      attrs = %{
        leave_type_id: leave_type.id,
        kind: kind,
        date: ask_date("Date", state.as_at),
        amount: Decimal.new(ask("Amount (negative to take away)")),
        expires_on: ask_optional_date("Expires on (blank for never)"),
        reason: blank_to_nil(ask("Reason#{if kind == :adjustment, do: " (required)"}"))
      }

      report(Leave.create_balance_entry(person, actor, attrs))
    end
  end

  # ── organisation & policies ─────────────────────────────────────────────────

  defp org_menu(state) do
    IO.puts("""

    ── Organisation & policies ──
      1  Show organisation        5  Policies & entitlements
      2  Amend organisation       6  Public holidays in a range
      3  Leave types              7  Add a public holiday
      4  Create a leave type
      blank  back\
    """)

    case ask("Choose") do
      "" -> :ok
      "1" -> again(state, &org_menu/1, &show_org/1)
      "2" -> amend_org(state)
      "3" -> again(state, &org_menu/1, &list_leave_types/1)
      "4" -> again(state, &org_menu/1, &create_leave_type/1)
      "5" -> again(state, &org_menu/1, &show_policies/1)
      "6" -> again(state, &org_menu/1, &list_holidays/1)
      "7" -> again(state, &org_menu/1, &create_holiday/1)
      _ -> org_menu(state)
    end
  end

  defp show_org(state) do
    org = state.org

    IO.puts("""

      #{org.name}
      full-time week   #{num(org.full_time_week_hours)}h
      standard day     #{num(org.standard_day_hours)}h
      year starts      month #{org.year_start_month}
      tracked from     #{org.tracked_from}\
    """)
  end

  defp amend_org(state) do
    org = state.org

    attrs = %{
      name: ask_default("Name", org.name),
      full_time_week_hours: ask_default("Full-time week hours", num(org.full_time_week_hours)),
      standard_day_hours: ask_default("Standard day hours", num(org.standard_day_hours)),
      year_start_month: ask_default("Year start month", to_string(org.year_start_month)),
      tracked_from: ask_date("Tracked from", org.tracked_from)
    }

    case Org.update_organisation(org, state.actor, attrs) do
      {:ok, updated} ->
        IO.puts("  ✓ #{updated.name}")
        org_menu(%{state | org: updated})

      {:error, changeset} ->
        print_errors(changeset)
        org_menu(state)
    end
  end

  defp list_leave_types(state) do
    IO.puts("")

    Enum.each(leave_types(state), fn type ->
      IO.puts("  #{type.position}. #{pad(type.name, 26)} in #{type.unit}#{archived(type)}")
    end)
  end

  defp archived(%{archived_at: nil}), do: ""
  defp archived(type), do: "  archived #{type.archived_at}"

  defp create_leave_type(state) do
    attrs = %{
      name: ask("Name"),
      unit: ask_choice("Unit", [:hours, :days]),
      position:
        String.to_integer(ask_default("Position", to_string(length(leave_types(state)) + 1)))
    }

    report(Policies.create_leave_type(state.org, state.actor, attrs), & &1.name)
  end

  defp show_policies(state) do
    range = Date.range(state.org.tracked_from, ~D[2099-12-31])

    Enum.each(policies(state.org), fn policy ->
      IO.puts("\n  #{policy.name}")

      Enum.each(Policies.entitlements(policy.id, range), fn entitlement ->
        IO.puts("    " <> describe_entitlement(entitlement))
      end)
    end)
  end

  defp describe_entitlement(entitlement) do
    "#{pad(entitlement.leave_type.name, 24)} #{pad(to_string(entitlement.amount_source), 16)}" <>
      " #{pad(amount(entitlement), 46)} #{pad(expiry(entitlement), 18)}" <>
      " from #{entitlement.effective_from}#{fte_note(entitlement)}"
  end

  defp amount(%{amount_source: :fixed} = entitlement) do
    "#{num(entitlement.grant_amount)} per #{entitlement.grant_period}" <>
      " on #{entitlement.grant_basis} (#{entitlement.grant_timing})"
  end

  defp amount(%{amount_source: :public_holidays}), do: "the calendar's own"
  defp amount(_entitlement), do: "nothing granted"

  defp expiry(%{expiry_rule: :cap} = entitlement), do: "cap #{num(entitlement.rollover_cap)}"

  defp expiry(%{expiry_rule: :window} = entitlement),
    do: "window #{entitlement.expiry_window_days}d"

  defp expiry(entitlement), do: to_string(entitlement.expiry_rule)

  defp fte_note(%{pro_rated_by_fte: true}), do: "  pro-rated"
  defp fte_note(_entitlement), do: ""

  defp list_holidays(state) do
    with %Calendar{} = calendar <- choose_calendar(state) do
      range = ask_range(state)

      IO.puts("")

      calendar.id
      |> Org.observed_holidays(range)
      |> Enum.each(&IO.puts("  #{&1.date}  #{&1.name}"))
    end
  end

  defp create_holiday(state) do
    with %Calendar{} = calendar <- choose_calendar(state) do
      attrs = %{date: ask_date("Date", state.as_at), name: ask("Name")}

      report(Org.create_public_holiday(calendar, state.actor, attrs), & &1.name)
    end
  end

  # ── audit ───────────────────────────────────────────────────────────────────

  defp audit(state) do
    limit = String.to_integer(ask_default("How many entries?", "25"))

    entries =
      Repo.all(
        from entry in Entry,
          order_by: [desc: entry.inserted_at],
          limit: ^limit,
          preload: [:actor, :subject_person]
      )

    IO.puts("")

    Enum.each(entries, fn entry ->
      IO.puts(
        "  #{entry.inserted_at}  #{pad(entry.action, 28)}" <>
          " by #{pad(who(entry.actor), 16)} about #{pad(who(entry.subject_person), 16)}" <>
          " #{inspect(Map.keys(entry.changes))}"
      )
    end)

    state
  end

  # ── choosing ────────────────────────────────────────────────────────────────

  defp choose_person(org, prompt), do: choose(labelled(people(org)), prompt)

  defp choose_policy(state), do: choose(labelled(policies(state.org)), "Which policy?")
  defp choose_calendar(state), do: choose(labelled(calendars(state.org)), "Which calendar?")
  defp choose_leave_type(state, prompt), do: choose(labelled(leave_types(state)), prompt)

  defp choose_request(state, prompt, status \\ :any) do
    state.org
    |> requests()
    |> Enum.filter(&(status == :any or &1.status == status))
    |> Enum.map(&{describe_request(&1), &1})
    |> choose(prompt)
  end

  defp labelled(records), do: Enum.map(records, &{&1.name, &1})

  defp choose([], prompt) do
    IO.puts("  Nothing to choose for: #{prompt}")
    nil
  end

  defp choose(options, prompt) do
    IO.puts("")

    options
    |> Enum.with_index(1)
    |> Enum.each(fn {{label, _}, i} -> IO.puts("  #{i}. #{label}") end)

    case ask(prompt <> " (blank to skip)") do
      "" -> nil
      answer -> pick(options, Integer.parse(answer))
    end
  end

  defp pick(options, {index, _rest}) when index >= 1 do
    case Enum.at(options, index - 1) do
      nil -> nil
      {_label, value} -> value
    end
  end

  defp pick(_options, _parsed), do: nil

  # ── asking ──────────────────────────────────────────────────────────────────

  defp ask(prompt) do
    case IO.gets(prompt <> ": ") do
      :eof -> System.halt(0)
      {:error, _reason} -> System.halt(1)
      line -> String.trim(line)
    end
  end

  defp ask_default(prompt, default) do
    case ask("#{prompt} [#{default}]") do
      "" -> default
      answer -> answer
    end
  end

  defp ask_date(prompt, default) do
    case Date.from_iso8601(ask_default(prompt, to_string(default))) do
      {:ok, date} ->
        date

      {:error, _reason} ->
        IO.puts("  Not a date. Try 2026-08-22.")
        ask_date(prompt, default)
    end
  end

  defp ask_range(state) do
    first = ask_date("From", state.as_at)

    Date.range(first, ask_date("To", first))
  end

  defp ask_choice(prompt, values) do
    answer = ask_default("#{prompt} (#{Enum.join(values, "/")})", hd(values))

    Enum.find(values, hd(values), &(to_string(&1) == answer))
  end

  defp ask_optional_date(prompt) do
    case ask(prompt) do
      "" -> nil
      answer -> ask_date(prompt, answer)
    end
  end

  defp need_actor(%{actor: nil}) do
    IO.puts("  That needs somebody to be acting. Choose an actor from the main menu.")
    nil
  end

  defp need_actor(state), do: state.actor

  # ── reporting ───────────────────────────────────────────────────────────────

  defp report(result, describe \\ &short(&1.id))

  defp report({:ok, record}, describe), do: IO.puts("  ✓ #{describe.(record)}")
  defp report({:error, :forbidden}, _describe), do: IO.puts("  ✗ forbidden for this actor")
  defp report({:error, changeset}, _describe), do: print_errors(changeset)

  defp outcome(request), do: "#{request.status} #{short(request.id)}"

  defp print_errors(changeset) do
    IO.puts("  ✗ rejected:")

    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.each(fn {field, messages} -> IO.puts("      #{field}: #{inspect(messages)}") end)
  end

  defp section(state, fun) do
    safely(fn -> fun.(state) end)
    menu(state)
  end

  defp safely(fun) do
    fun.()
  rescue
    error -> IO.puts("\n  !! #{Exception.message(error)}")
  end

  defp again(state, menu, action) do
    action.(state)
    menu.(state)
  end

  # ── lookups the contexts don't expose yet ───────────────────────────────────

  defp people(org) do
    Repo.all(from p in Person, where: p.organisation_id == ^org.id, order_by: p.name)
  end

  defp policies(org) do
    Repo.all(from p in LeavePolicy, where: p.organisation_id == ^org.id, order_by: p.name)
  end

  defp calendars(org) do
    Repo.all(from c in Calendar, where: c.organisation_id == ^org.id, order_by: c.name)
  end

  defp requests(org) do
    Repo.all(
      from request in Request,
        join: person in assoc(request, :person),
        where: person.organisation_id == ^org.id,
        order_by: [desc: request.inserted_at],
        limit: 40,
        preload: [:days, person: person]
    )
  end

  defp succession(person, schema) do
    Repo.all(from row in schema, where: row.person_id == ^person.id)
  end

  defp leave_types(state), do: Policies.leave_types(state.org.id)

  defp leave_type_name(id), do: Repo.get!(LeaveType, id).name
  defp policy_name(id), do: Repo.get!(LeavePolicy, id).name
  defp calendar_name(id), do: Repo.get!(Calendar, id).name

  # ── formatting ──────────────────────────────────────────────────────────────

  defp who(nil), do: "the system"
  defp who(person), do: "#{person.name} (#{person.role})"

  defp id_of(nil), do: nil
  defp id_of(record), do: record.id

  defp short(id), do: String.slice(id, 0, 8)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp num(nil), do: "-"

  defp num(%Decimal{} = decimal) do
    decimal |> Decimal.round(4) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  defp num(other), do: to_string(other)

  defp pad(value, width), do: String.pad_trailing(to_string(value), width)
end

Tui.run()
