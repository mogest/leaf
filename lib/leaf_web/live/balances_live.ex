defmodule LeafWeb.BalancesLive do
  @moduledoc """
  Everything somebody holds, and how whichever one they are reading was arrived at.

  Nothing here is stored — every figure is worked out from the person's dates, hours, policy and
  the leave they filed — so the date at the top is the whole page's question, and one ahead of
  today reads every account as it will stand.

  A type nothing is held in is listed all the same, along with one their policy offers but grants
  nothing for: what somebody may ask for is as much part of this page as what they have, and
  nothing held is an answer.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave
  alias Leaf.Ledger
  alias Leaf.People
  alias Leaf.Policies

  @kinds %{
    opening_balance: "Brought in",
    adjustment: "Adjusted",
    grant: "Granted",
    accrual: "Accrued",
    taken: "Taken",
    expiry: "Lapsed",
    rollover_cap: "Over the cap"
  }

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    {:noreply, opened(socket, person(socket, params["person_id"]), params)}
  end

  @impl Phoenix.LiveView
  def handle_event("as-at", %{"ledger" => %{"as_at" => as_at}}, socket) do
    %{person: person, mine?: mine?, selected: selected} = socket.assigns

    {:noreply, push_patch(socket, to: path(person, mine?, selected, as_at))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="balances" viewer={@viewer}>
      <header>
        <h1>Balances</h1>
        <.link :if={!@mine?} navigate={~p"/people/#{@person}"}>{@person.name}</.link>
      </header>

      <.form id="as-at" for={@form} phx-change="as-at">
        <.input field={@form[:as_at]} type="date" label="As at" />
      </.form>

      <p :if={@nothing}>{@nothing}</p>

      <nav :if={@accounts != []}>
        <ul>
          <li :for={account <- @accounts}>
            <.link patch={account.path} aria-current={account.current? && "page"}>
              <span>{account.name}</span>
              <span>{account.amount}</span>
            </.link>
          </li>
        </ul>
      </nav>

      <div :if={@account}>
        <section class="balance-sheet">
          <header>
            <h2>{@account.name}</h2>
            <p>as at {@account.as_at}</p>
          </header>
          <dl>
            <dt>Held</dt>
            <dd>{@account.held}</dd>
            <dd :if={@account.awaiting} data-awaiting>{@account.awaiting}</dd>
          </dl>
        </section>

        <section>
          <header>
            <h2>Lots held</h2>
          </header>
          <ol :if={@account.lots != []}>
            <li :for={lot <- @account.lots}>
              <span>{lot.amount}</span>
              <span>{lot.expires}</span>
            </li>
          </ol>
          <p :if={@account.lots == []}>Nothing held.</p>
        </section>

        <section>
          <header>
            <h2>How it was arrived at</h2>
          </header>
          <table :if={@account.movements != []}>
            <thead>
              <tr>
                <th scope="col">Date</th>
                <th scope="col">What</th>
                <th scope="col">Amount</th>
                <th scope="col">Lapses</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={movement <- @account.movements}>
                <td>{movement.date}</td>
                <td>{movement.kind}</td>
                <td data-tone={movement.tone}>{movement.amount}</td>
                <td>{movement.expires}</td>
              </tr>
            </tbody>
          </table>
          <p :if={@account.movements == []}>Nothing has happened to it yet.</p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp person(socket, nil), do: socket.assigns.current_person

  defp person(_socket, id) do
    {:ok, person} = People.fetch_person(id)

    person
  end

  defp opened(socket, person, params) do
    case People.oversees?(socket.assigns.current_person, person) do
      true -> shown(socket, person, params)
      false -> refused(socket)
    end
  end

  defp refused(socket) do
    socket
    |> put_flash(:error, "Those balances are not yours to read.")
    |> push_navigate(to: ~p"/")
  end

  defp shown(socket, person, params) do
    as_at = as_at(params["as_at"])
    mine? = person.id == socket.assigns.current_person.id

    case chosen(accounts(person, as_at), person, params["leave_type_id"]) do
      {:ok, accounts, chosen} -> listed(socket, person, mine?, as_at, accounts, chosen)
      :error -> missing(socket, person, mine?, as_at)
    end
  end

  defp missing(socket, person, mine?, as_at) do
    socket
    |> put_flash(:error, "There is no account to show for that.")
    |> push_navigate(to: path(person, mine?, nil, to_string(as_at)))
  end

  defp listed(socket, person, mine?, as_at, accounts, chosen) do
    selected = selected(chosen)

    socket
    |> assign(:page_title, title(person, mine?))
    |> assign(:person, person)
    |> assign(:mine?, mine?)
    |> assign(:selected, selected)
    |> assign(:form, to_form(%{"as_at" => to_string(as_at)}, as: :ledger))
    |> assign(:accounts, Enum.map(accounts, &listing(&1, person, mine?, as_at, selected)))
    |> assign(:account, account(chosen, Ledger.awaiting(person), as_at))
    |> assign(:nothing, nothing(accounts, person, mine?, as_at))
  end

  defp title(_person, true), do: "Balances"
  defp title(person, false), do: "#{person.name}'s balances"

  # Every type the person holds an account in, and every one their policy offers them. The two
  # overlap in all but the extremes: a type granting nothing holds no account until there is leave
  # against it, and one they have left behind holds what it holds without being on offer any more.
  defp accounts(person, as_at) do
    case Ledger.ready?(person, as_at) do
      true -> held(person, as_at)
      false -> []
    end
  end

  defp held(person, as_at) do
    statements = Map.new(Ledger.statements(person, as_at), &{&1.leave_type.id, &1})

    statements
    |> Map.values()
    |> Enum.map(& &1.leave_type)
    |> Enum.concat(Leave.requestable(person, Date.range(as_at, as_at)))
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.position, &1.name})
    |> Enum.map(&{&1, statements[&1.id]})
  end

  defp chosen(accounts, _person, nil), do: {:ok, accounts, List.first(accounts)}

  defp chosen(accounts, person, id) do
    case Enum.find(accounts, fn {leave_type, _statement} -> leave_type.id == id end) do
      nil -> unlisted(accounts, person, id)
      found -> {:ok, accounts, found}
    end
  end

  # A date can be read at which a type held nothing and was not yet offered, and reading one is
  # not an error: it is listed for as long as it is being read, so what the page is showing is
  # always one of the accounts standing beside it.
  defp unlisted(accounts, person, id) do
    case Policies.fetch_leave_type(id) do
      {:ok, leave_type} -> theirs(accounts, leave_type, person.organisation_id)
      :error -> :error
    end
  end

  defp theirs(accounts, %{organisation_id: organisation_id} = leave_type, organisation_id) do
    chosen = {leave_type, nil}

    {:ok, Enum.sort_by([chosen | accounts], &order/1), chosen}
  end

  defp theirs(_accounts, _leave_type, _organisation_id), do: :error

  defp order({leave_type, _statement}), do: {leave_type.position, leave_type.name}

  defp selected(nil), do: nil
  defp selected({leave_type, _statement}), do: leave_type.id

  # Every link on the page carries the date the page is being read at, so stepping between
  # accounts does not quietly step back to today.
  defp listing({leave_type, statement}, person, mine?, as_at, selected) do
    %{
      name: leave_type.name,
      amount: figure(statement, leave_type),
      path: path(person, mine?, leave_type.id, to_string(as_at)),
      current?: leave_type.id == selected
    }
  end

  defp account(nil, _awaiting, _as_at), do: nil

  defp account({leave_type, statement}, awaiting, as_at) do
    %{
      name: leave_type.name,
      as_at: Wording.date(as_at),
      held: figure(statement, leave_type),
      awaiting: asked(awaiting[leave_type.id], leave_type.unit),
      lots: lots(statement, leave_type),
      movements: movements(statement, leave_type)
    }
  end

  defp figure(nil, leave_type), do: Wording.figure(Decimal.new(0), leave_type.unit)
  defp figure(statement, leave_type), do: Wording.figure(statement.balance, leave_type.unit)

  defp asked(nil, _unit), do: nil
  defp asked(amount, unit), do: "#{Wording.figure(amount, unit)} awaiting approval"

  defp lots(nil, _leave_type), do: []
  defp lots(statement, leave_type), do: Enum.map(statement.lots, &lot(&1, leave_type))

  defp lot(lot, leave_type) do
    %{amount: Wording.figure(lot.amount, leave_type.unit), expires: lapses(lot.expires_on)}
  end

  defp lapses(nil), do: "does not lapse"
  defp lapses(date), do: "lapses #{Wording.date(date)}"

  defp movements(nil, _leave_type), do: []

  defp movements(statement, leave_type),
    do: Enum.map(statement.movements, &movement(&1, leave_type))

  defp movement(movement, leave_type) do
    %{
      date: Wording.date(movement.date),
      kind: Map.fetch!(@kinds, movement.kind),
      amount: Wording.figure(movement.amount, leave_type.unit),
      expires: Wording.date(movement.expires_on),
      tone: tone(movement.amount)
    }
  end

  defp tone(amount) do
    case Decimal.negative?(amount) do
      true -> "spent"
      false -> nil
    end
  end

  defp nothing([_account | _rest], _person, _mine?, _as_at), do: nil

  defp nothing([], person, mine?, as_at) do
    case {Ledger.ready?(person, as_at), mine?} do
      {true, true} ->
        "You hold no balance in anything."

      {true, false} ->
        "They hold no balance in anything."

      {false, true} ->
        "No balance can be worked out until you are on a work pattern throughout."

      {false, false} ->
        "No balance can be worked out until they are on a work pattern throughout."
    end
  end

  defp path(_person, true, nil, as_at), do: ~p"/balances?as_at=#{as_at}"
  defp path(person, false, nil, as_at), do: ~p"/people/#{person}/balances?as_at=#{as_at}"
  defp path(_person, true, id, as_at), do: ~p"/balances/#{id}?as_at=#{as_at}"
  defp path(person, false, id, as_at), do: ~p"/people/#{person}/balances/#{id}?as_at=#{as_at}"

  defp as_at(nil), do: Date.utc_today()

  defp as_at(entered) do
    case Date.from_iso8601(entered) do
      {:ok, date} -> date
      {:error, _reason} -> Date.utc_today()
    end
  end
end
