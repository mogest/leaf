defmodule LeafWeb.PersonLive do
  @moduledoc """
  One person's whole record: their dates, the effective-dated facts that follow them, and what
  they hold.

  Everything effective-dated here can be put right after the fact (§4.4), so each succession is
  shown as its own list with the row it is made of editable and removable. Only an administrator
  sees those; a manager reading their report's page sees the record and nothing to change on it.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave
  alias Leaf.Ledger
  alias Leaf.Org
  alias Leaf.People
  alias Leaf.Policies

  @impl Phoenix.LiveView
  def mount(%{"person_id" => id}, _session, socket) do
    {:ok, person} = People.fetch_person(id)

    {:ok, opened(socket, person, People.oversees?(socket.assigns.current_person, person))}
  end

  @impl Phoenix.LiveView
  def handle_event("remove-work-pattern", %{"id" => id}, socket) do
    {:ok, pattern} = People.fetch_work_pattern(id)

    {:noreply, socket |> removed(People.delete_work_pattern(pattern, actor(socket))) |> loaded()}
  end

  def handle_event("remove-policy-assignment", %{"id" => id}, socket) do
    {:ok, assignment} = People.fetch_policy_assignment(id)

    {:noreply,
     socket |> removed(People.delete_policy_assignment(assignment, actor(socket))) |> loaded()}
  end

  def handle_event("remove-calendar-assignment", %{"id" => id}, socket) do
    {:ok, assignment} = People.fetch_calendar_assignment(id)

    {:noreply,
     socket |> removed(People.delete_calendar_assignment(assignment, actor(socket))) |> loaded()}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="people" viewer={@viewer}>
      <header>
        <h1>{@person.name}</h1>
        <.link :if={@admin?} class="button" navigate={~p"/people/#{@person}/edit"}>Amend</.link>
      </header>

      <section>
        <header>
          <h2>Who they are</h2>
        </header>
        <dl>
          <dt>Email</dt>
          <dd>{@person.email}</dd>
          <dt>Role</dt>
          <dd>{@role}</dd>
          <dt>Employment</dt>
          <dd>{@employment}</dd>
          <dt>Born</dt>
          <dd>{@born}</dd>
          <dt>Manager</dt>
          <dd>{@manager}</dd>
        </dl>
      </section>

      <section>
        <header>
          <h2>Balances</h2>
          <p>as at today</p>
        </header>
        <ol :if={@balances != []}>
          <li :for={balance <- @balances}>
            <.link navigate={balance.path}>{balance.name}</.link>
            <span>{balance.amount}</span>
          </li>
        </ol>
        <p :if={@balances == []}>{@nothing_held}</p>
      </section>

      <section>
        <header>
          <h2>Work patterns</h2>
          <.link :if={@admin?} navigate={~p"/people/#{@person}/work-patterns/new"}>Add one</.link>
        </header>
        <ol :if={@patterns != []}>
          <li :for={pattern <- @patterns}>
            <span>{pattern.from}</span>
            <span>{pattern.hours}</span>
            <span>{pattern.weekly}</span>
            <.link :if={@admin?} navigate={pattern.path}>Amend</.link>
            <button
              :if={@admin?}
              type="button"
              phx-click="remove-work-pattern"
              phx-value-id={pattern.id}
              data-confirm="Remove this work pattern? Whatever preceded it runs on."
            >
              Remove
            </button>
          </li>
        </ol>
        <p :if={@patterns == []}>No work pattern on record, so no balance can be worked out.</p>
      </section>

      <section>
        <header>
          <h2>Leave policies</h2>
          <.link :if={@admin?} navigate={~p"/people/#{@person}/policy-assignments/new"}>
            Assign one
          </.link>
        </header>
        <ol :if={@policies != []}>
          <li :for={assignment <- @policies}>
            <span>{assignment.from}</span>
            <.link navigate={assignment.path}>{assignment.name}</.link>
            <button
              :if={@admin?}
              type="button"
              phx-click="remove-policy-assignment"
              phx-value-id={assignment.id}
              data-confirm="Remove this assignment? Whatever preceded it runs on."
            >
              Remove
            </button>
          </li>
        </ol>
        <p :if={@policies == []}>On no policy, so nothing is granted.</p>
      </section>

      <section>
        <header>
          <h2>Holiday calendars</h2>
          <.link :if={@admin?} navigate={~p"/people/#{@person}/calendar-assignments/new"}>
            Assign one
          </.link>
        </header>
        <ol :if={@calendars != []}>
          <li :for={assignment <- @calendars}>
            <span>{assignment.from}</span>
            <.link navigate={assignment.path}>{assignment.name}</.link>
            <button
              :if={@admin?}
              type="button"
              phx-click="remove-calendar-assignment"
              phx-value-id={assignment.id}
              data-confirm="Remove this assignment? Whatever preceded it runs on."
            >
              Remove
            </button>
          </li>
        </ol>
        <p :if={@calendars == []}>Observing no calendar, so no public holidays.</p>
      </section>

      <section>
        <header>
          <h2>Balances entered by hand</h2>
          <.link :if={@admin?} navigate={~p"/people/#{@person}/balance-entries/new"}>Record one</.link>
        </header>
        <table :if={@entries != []}>
          <thead>
            <tr>
              <th scope="col">Date</th>
              <th scope="col">What</th>
              <th scope="col">Leave type</th>
              <th scope="col">Amount</th>
              <th scope="col">Lapses</th>
              <th scope="col">Reason</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={entry <- @entries}>
              <td>{entry.date}</td>
              <td>{entry.kind}</td>
              <td>{entry.leave_type}</td>
              <td>{entry.amount}</td>
              <td>{entry.expires}</td>
              <td>{entry.reason}</td>
            </tr>
          </tbody>
        </table>
        <p :if={@entries == []}>Nothing has been entered by hand.</p>
      </section>

      <Parts.requests requests={@requests} title="Requests">
        <:empty>They have not asked for any leave.</:empty>
      </Parts.requests>
    </Layouts.app>
    """
  end

  defp opened(socket, person, true) do
    socket |> assign(:person, person) |> assign(:page_title, person.name) |> loaded()
  end

  defp opened(socket, _person, false) do
    socket |> put_flash(:error, "That record is not yours to read.") |> push_navigate(to: ~p"/")
  end

  defp loaded(socket) do
    person = socket.assigns.person
    today = Date.utc_today()
    {:ok, organisation} = Org.fetch_organisation(person.organisation_id)
    leave_types = Map.new(Policies.leave_types(organisation.id), &{&1.id, &1})

    socket
    |> assign(:admin?, socket.assigns.current_person.role == :admin)
    |> assign(:role, role(person))
    |> assign(:employment, employment(person))
    |> assign(:born, Wording.date(person.birth_date) || "not on record")
    |> assign(:manager, manager(person))
    |> assign(:balances, balances(person, today))
    |> assign(:nothing_held, nothing_held(person, today))
    |> assign(
      :patterns,
      Enum.map(People.work_patterns(person), &pattern(&1, person, organisation))
    )
    |> assign(:policies, Enum.map(People.policy_assignments(person), &policy/1))
    |> assign(:calendars, Enum.map(People.calendar_assignments(person), &calendar/1))
    |> assign(:entries, entries(person, leave_types))
    |> assign(:requests, Enum.map(Leave.requests(person), &Wording.filed(&1, today)))
  end

  defp actor(socket), do: socket.assigns.current_person

  defp role(%{role: :admin}), do: "Administrator"
  defp role(_person), do: "Member"

  defp employment(%{employment_end_date: nil} = person) do
    "from #{Wording.date(person.employment_start_date)}"
  end

  defp employment(person) do
    "#{Wording.date(person.employment_start_date)} – #{Wording.date(person.employment_end_date)}"
  end

  defp manager(person) do
    case People.fetch_manager(person) do
      {:ok, manager} -> manager.name
      :error -> "nobody, so an administrator decides"
    end
  end

  defp balances(person, today) do
    case Ledger.ready?(person, today) do
      true -> person |> Ledger.statements(today) |> Enum.map(&balance(&1, person))
      false -> []
    end
  end

  defp balance(statement, person) do
    %{
      name: statement.leave_type.name,
      amount: Wording.figure(statement.balance, statement.leave_type.unit),
      path: ~p"/people/#{person}/balances/#{statement.leave_type}"
    }
  end

  defp nothing_held(person, today) do
    case Ledger.ready?(person, today) do
      true -> "They hold no balance in anything."
      false -> "No balance can be worked out until they are on a work pattern throughout."
    end
  end

  defp pattern(pattern, person, organisation) do
    %{
      id: pattern.id,
      from: "from #{Wording.date(pattern.effective_from)}",
      hours: hours(pattern),
      weekly: weekly(pattern, organisation),
      path: ~p"/people/#{person}/work-patterns/#{pattern}"
    }
  end

  defp hours(pattern) do
    [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]
    |> Enum.map_join(" ", &Wording.number(Map.fetch!(pattern, :"#{&1}_hours")))
  end

  defp weekly(pattern, organisation) do
    weekly = People.weekly_hours(pattern)
    fte = People.fte(pattern, organisation.full_time_week_hours)

    "#{Wording.number(weekly)} hours a week, #{Wording.number(fte)} FTE"
  end

  defp policy(assignment) do
    %{
      id: assignment.id,
      from: "from #{Wording.date(assignment.effective_from)}",
      name: assignment.leave_policy.name,
      path: ~p"/settings/policies/#{assignment.leave_policy}"
    }
  end

  defp calendar(assignment) do
    %{
      id: assignment.id,
      from: "from #{Wording.date(assignment.effective_from)}",
      name: assignment.holiday_calendar.name,
      path: ~p"/settings/calendars/#{assignment.holiday_calendar}"
    }
  end

  # Every entry, whatever it is dated: an import of a balance held before go-live is the whole
  # story up to it, and an adjustment can be dated ahead of today.
  defp entries(person, leave_types) do
    person |> Leave.balance_entries() |> Enum.map(&entry(&1, leave_types))
  end

  defp entry(entry, leave_types) do
    leave_type = Map.fetch!(leave_types, entry.leave_type_id)

    %{
      date: Wording.date(entry.date),
      kind: kind(entry.kind),
      leave_type: leave_type.name,
      amount: Wording.figure(entry.amount, leave_type.unit),
      expires: Wording.date(entry.expires_on),
      reason: entry.reason
    }
  end

  defp kind(:opening_balance), do: "Brought in"
  defp kind(:adjustment), do: "Adjusted"

  defp removed(socket, {:ok, _record}), do: put_flash(socket, :info, "Removed.")

  defp removed(socket, {:error, _changeset}) do
    put_flash(socket, :error, "That would not come off the record.")
  end
end
