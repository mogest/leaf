defmodule LeafWeb.BalancesLive do
  @moduledoc """
  Everything somebody holds, and how whichever one they are reading was arrived at.

  Nothing here is stored — every figure is worked out from the person's dates, hours, policy and
  the leave they filed — so the date at the top is the whole page's question, and one ahead of
  today reads every account as it will stand.

  A type nothing is held in is listed all the same, along with one their policy offers but grants
  nothing for: what somebody may ask for is as much part of this page as what they have, and
  nothing held is an answer. One they have never been granted anything in shows no figure, at any
  date, since the only figure it has is the leave taken with a minus in front.
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
    accrual: "Earned",
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
  @role :member
  def handle_event("as-at", %{"ledger" => %{"as_at" => as_at}}, socket) do
    %{person: person, mine?: mine?, selected: selected} = socket.assigns

    {:noreply, push_patch(socket, to: path(person, mine?, selected, as_at))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="balances" rail={@rail} viewer={@viewer}>
      <header>
        <nav :if={!@mine?}>
          <.link navigate={~p"/people"}>People</.link>
          <.link navigate={~p"/people/#{@person}"}>{@person.name}</.link>
        </nav>
        <h1>{@heading}</h1>
        <p>Employed {@employment}</p>
      </header>

      <.form id="as-at" for={@form} phx-change="as-at">
        <.input field={@form[:as_at]} type="date" label="As at" phx-debounce="500" />
      </.form>

      <p :if={@nothing}>{@nothing}</p>

      <nav :if={@accounts != []}>
        <ul>
          <li :for={account <- @accounts}>
            <.link patch={account.path} aria-current={account.current? && "page"}>
              <span>{account.name}</span>
              <span :if={account.amount}>{account.amount}</span>
            </.link>
          </li>
        </ul>
      </nav>

      <div :if={@account}>
        <section class="balance-sheet">
          <header>
            <h2>{@account.name} <small>as at {@account.as_at}</small></h2>
          </header>
          <dl :if={@account.accrued}>
            <dt>Accrued</dt>
            <dd>{@account.accrued}</dd>
            <dd :if={@account.awaiting} data-awaiting>{@account.awaiting}</dd>
          </dl>
          <p :if={!@account.accrued}>Recorded as it is taken; nothing accrues.</p>
          <p :if={!@account.accrued && @account.awaiting} data-awaiting>{@account.awaiting}</p>
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

  defp person(socket, nil), do: {:ok, socket.assigns.current_person}
  defp person(_socket, id), do: People.fetch_person(id)

  # An id naming nobody answers as one naming somebody whose balances are not theirs to read.
  defp opened(socket, {:ok, person}, params) do
    case People.oversees?(socket.assigns.current_person, person) do
      true -> shown(socket, person, params)
      false -> refused(socket)
    end
  end

  defp opened(socket, :error, _params), do: refused(socket)

  defp refused(socket) do
    socket
    |> put_flash(:error, "Those balances are not yours to read.")
    |> push_navigate(to: ~p"/")
  end

  defp shown(socket, person, params) do
    as_at = as_at(params["as_at"], socket.assigns.current_person)
    mine? = person.id == socket.assigns.current_person.id
    ready? = Ledger.ready?(person, as_at)

    case accounts(person, as_at, ready?, params["leave_type_id"]) do
      {:ok, accounts, chosen} ->
        socket
        |> listed(person, mine?, as_at, accounts, chosen)
        |> assign(:nothing, nothing(accounts, ready?, mine?))

      :error ->
        missing(socket, person, mine?, as_at)
    end
  end

  defp missing(socket, person, mine?, as_at) do
    socket
    |> put_flash(:error, "There is no account to show for that.")
    |> push_navigate(to: path(person, mine?, nil, to_string(as_at)))
  end

  defp listed(socket, person, mine?, as_at, accounts, chosen) do
    selected = selected(chosen)
    granted = Ledger.granted(person)
    listings = Enum.map(accounts, &listing(&1, granted, person, mine?, as_at, selected))

    socket
    |> assign(:page_title, title(person, mine?))
    |> assign(:heading, heading(mine?))
    |> assign(:rail, rail(mine?))
    |> assign(:person, person)
    |> assign(:employment, Wording.employment(person))
    |> assign(:mine?, mine?)
    |> assign(:selected, selected)
    |> assign(:form, to_form(%{"as_at" => to_string(as_at)}, as: :ledger))
    |> assign(:accounts, listings)
    |> assign(:account, account(chosen, granted, person, as_at))
  end

  defp title(_person, true), do: "Your balances"
  defp title(person, false), do: "#{person.name}'s balances"

  defp heading(true), do: "Your balances"
  defp heading(false), do: "Balances"

  defp rail(true), do: nil
  defp rail(false), do: "people"

  # A record too incomplete to work balances out of lists nothing rather than what is offered at
  # nothing, which would read as a balance.
  defp accounts(_person, _as_at, false, _id), do: {:ok, [], nil}
  defp accounts(person, as_at, true, id), do: chosen(held(person, as_at), person, id)

  # Every type the person holds an account in, and every one their policy offers them. The two
  # overlap in all but the extremes: a type granting nothing holds no account until there is leave
  # against it, and one they have left behind holds what it holds without being on offer any more.
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
  defp listing({leave_type, statement}, granted, person, mine?, as_at, selected) do
    %{
      name: leave_type.name,
      amount: accrued(statement, leave_type, granted),
      path: path(person, mine?, leave_type.id, to_string(as_at)),
      current?: leave_type.id == selected
    }
  end

  defp account(nil, _granted, _person, _as_at), do: nil

  defp account({leave_type, statement}, granted, person, as_at) do
    %{
      name: leave_type.name,
      as_at: Wording.date(as_at),
      accrued: accrued(statement, leave_type, granted),
      awaiting: Wording.asked(Ledger.awaiting(person)[leave_type.id], leave_type.unit),
      lots: lots(statement, leave_type),
      movements: movements(statement, leave_type)
    }
  end

  defp accrued(statement, leave_type, granted) do
    case {MapSet.member?(granted, leave_type.id), statement} do
      {false, _statement} -> nil
      {true, nil} -> Wording.figure(Decimal.new(0), leave_type.unit)
      {true, statement} -> Wording.figure(statement.balance, leave_type.unit)
    end
  end

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

  defp nothing([], ready?, true), do: Wording.no_balance(ready?, "you")
  defp nothing([], ready?, false), do: Wording.no_balance(ready?, "they")
  defp nothing(_accounts, _ready?, _mine?), do: nil

  defp path(_person, true, nil, as_at), do: ~p"/balances?as_at=#{as_at}"
  defp path(person, false, nil, as_at), do: ~p"/people/#{person}/balances?as_at=#{as_at}"
  defp path(_person, true, id, as_at), do: ~p"/balances/#{id}?as_at=#{as_at}"
  defp path(person, false, id, as_at), do: ~p"/people/#{person}/balances/#{id}?as_at=#{as_at}"

  defp as_at(entered, viewer) when is_binary(entered) do
    case Date.from_iso8601(entered) do
      {:ok, date} -> date
      {:error, _reason} -> People.today(viewer)
    end
  end

  defp as_at(_entered, viewer), do: People.today(viewer)
end
