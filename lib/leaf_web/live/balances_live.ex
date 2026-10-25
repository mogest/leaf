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

  How the one being read was arrived at is told a financial year at a time, opening on the year
  holding the date at the top.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave
  alias Leaf.Ledger
  alias Leaf.People
  alias Leaf.Policies
  alias LeafWeb.Chart

  @kinds %{
    opening_balance: "Opening balance",
    adjustment: "Adjusted",
    grant: "Granted",
    accrual: "Earned",
    taken: "Taken",
    booked: "Booked",
    expiry: "Expired",
    rollover_cap: "Over rollover cap",
    started: "Started",
    left: "Left"
  }

  @columns [:earned, :taken, :lost]

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
        <nav :if={!@mine?} aria-label="Breadcrumb">
          <.link navigate={~p"/people"}>People</.link>
          <.link navigate={~p"/people/#{@person}"}>{@person.name}</.link>
        </nav>
        <h1>{@heading}</h1>
      </header>

      <.form id="as-at" for={@form} phx-change="as-at">
        <.input field={@form[:as_at]} type="date" label="As at" phx-debounce="500" />
      </.form>

      <p :if={@nothing}>{@nothing}</p>

      <nav :if={@accounts != []} aria-label="Balances">
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
          <dl :if={@account.figures != []}>
            <%= for {label, figure} <- @account.figures do %>
              <dt>{label}</dt>
              <dd>{figure}</dd>
            <% end %>
            <dd :if={@account.awaiting} data-awaiting>{@account.awaiting}</dd>
          </dl>
          <p :if={@account.figures == []}>
            This leave doesn't build up. It's only recorded when taken.
          </p>
          <p :if={@account.figures == [] && @account.awaiting} data-awaiting>{@account.awaiting}</p>
        </section>

        <.history :if={@account.history} history={@account.history} />

        <section :if={@account.expiring != []}>
          <header>
            <h2>Expiry</h2>
          </header>
          <ol>
            <li :for={lot <- @account.expiring}>
              <span>{lot.amount}</span>
              <span>expiring {lot.expires}</span>
            </li>
          </ol>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :history, :map, required: true

  defp history(assigns) do
    ~H"""
    <section>
      <header>
        <h2>History</h2>
        <span>{@history.span}</span>
        <Parts.steps earlier={@history.earlier} later={@history.later} what="year" />
      </header>
      <.chart :if={@history.chart} chart={@history.chart} />
      <div>
        <table>
          <thead>
            <tr>
              <th scope="col">Month</th>
              <th scope="col">{@history.earned}</th>
              <th scope="col">Taken</th>
              <th scope="col">Lost</th>
              <th scope="col">Balance</th>
            </tr>
          </thead>
          <tbody :if={@history.brought_forward}>
            <tr>
              <th scope="row">{@history.opening}</th>
              <td></td>
              <td></td>
              <td></td>
              <td>{@history.brought_forward}</td>
            </tr>
          </tbody>
          <tbody :for={month <- @history.months} id={month.id}>
            <tr>
              <th scope="row">
                <button
                  type="button"
                  aria-expanded="false"
                  phx-click={JS.toggle_attribute({"aria-expanded", "true", "false"})}
                >
                  {month.name} <small :if={month.note}>{month.note}</small>
                </button>
              </th>
              <td :for={figure <- month.figures}>{figure}</td>
              <td>{month.balance}</td>
            </tr>
            <tr :for={line <- month.lines}>
              <td><span>{line.dates}</span> {line.what}</td>
              <td :for={figure <- line.figures}>{figure}</td>
              <td></td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  attr :chart, :map, required: true

  defp chart(assigns) do
    ~H"""
    <figure>
      <svg viewBox="0 0 600 200" role="group" aria-label={@chart.label}>
        <line x1="0" y1={@chart.zero} x2="600" y2={@chart.zero} />
        <line :for={x <- @chart.months} x1={x} y1="0" x2={x} y2="200" />
        <line :if={@chart.as_at} data-as-at x1={@chart.as_at.x} y1="0" x2={@chart.as_at.x} y2="200" />
        <polyline points={@chart.balance} />
        <polyline data-tone="spent" points={@chart.booked} />
        <g :for={loss <- @chart.losses}>
          <circle cx={loss.x} cy={loss.y} r="7" tabindex="0" role="img" aria-label={loss.label} />
          <foreignObject x={loss.label_x} y={loss.y + 14} width="360" height="200" aria-hidden="true">
            <p>{loss.label}</p>
          </foreignObject>
        </g>
      </svg>
      <figcaption>
        <span>{@chart.from}</span><span>{@chart.to}</span>
      </figcaption>
      <ul>
        <li>
          <svg width="16" height="16" aria-hidden="true"><polyline points="0,8 16,8" /></svg>Balance
        </li>
        <li :if={@chart.booked != ""}>
          <svg width="16" height="16" aria-hidden="true">
            <polyline data-tone="spent" points="0,8 16,8" />
          </svg>Booked
        </li>
        <li :if={@chart.losses != []}>
          <svg width="16" height="16" aria-hidden="true"><circle cx="8" cy="8" r="5" /></svg>Lost
        </li>
        <li :if={@chart.as_at}>
          <svg width="16" height="16" aria-hidden="true"><line data-as-at x1="8" y1="0" x2="8" y2="16" /></svg>{@chart.as_at.label}
        </li>
      </ul>
    </figure>
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
    |> put_flash(:error, "You don't have access to those balances.")
    |> push_navigate(to: ~p"/")
  end

  defp shown(socket, person, params) do
    as_at = as_at(params["as_at"], socket.assigns.current_person)
    mine? = person.id == socket.assigns.current_person.id
    ready? = Ledger.ready?(person, as_at)
    reading = %{person: person, mine?: mine?, as_at: as_at, year: year(params["year"])}

    case accounts(person, as_at, ready?, params["leave_type_id"]) do
      {:ok, accounts, chosen} ->
        socket
        |> listed(reading, accounts, chosen)
        |> assign(:nothing, nothing(accounts, ready?, mine?))

      :error ->
        missing(socket, person, mine?, as_at)
    end
  end

  defp missing(socket, person, mine?, as_at) do
    socket
    |> put_flash(:error, "No balance found for that leave type.")
    |> push_navigate(to: path(person, mine?, nil, to_string(as_at)))
  end

  defp listed(socket, reading, accounts, chosen) do
    %{person: person, mine?: mine?, as_at: as_at} = reading
    selected = selected(chosen)
    granted = Ledger.granted(person)
    listings = Enum.map(accounts, &listing(&1, granted, person, mine?, as_at, selected))

    socket
    |> assign(:page_title, title(person, mine?))
    |> assign(:heading, heading(mine?))
    |> assign(:rail, rail(mine?))
    |> assign(:person, person)
    |> assign(:mine?, mine?)
    |> assign(:selected, selected)
    |> assign(:form, to_form(%{"as_at" => to_string(as_at)}, as: :ledger))
    |> assign(:accounts, listings)
    |> assign(:account, account(chosen, granted, reading))
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
      amount: accrued(statement, leave_type, granted, :balance),
      path: path(person, mine?, leave_type.id, to_string(as_at)),
      current?: leave_type.id == selected
    }
  end

  defp account(nil, _granted, _reading), do: nil

  defp account({leave_type, statement}, granted, reading) do
    %{
      name: leave_type.name,
      as_at: Wording.date(reading.as_at),
      figures:
        figures(
          accrued(statement, leave_type, granted, :to_date),
          accrued(statement, leave_type, granted, :balance)
        ),
      awaiting: Wording.asked(Ledger.awaiting(reading.person)[leave_type.id], leave_type.unit),
      expiring: expiring(statement, leave_type),
      history: history(statement, MapSet.member?(granted, leave_type.id), reading)
    }
  end

  defp accrued(statement, leave_type, granted, figure) do
    case {MapSet.member?(granted, leave_type.id), statement} do
      {false, _statement} -> nil
      {true, nil} -> Wording.figure(Decimal.new(0), leave_type.unit)
      {true, statement} -> Wording.figure(Map.fetch!(statement, figure), leave_type.unit)
    end
  end

  defp figures(nil, nil), do: []
  defp figures(same, same), do: [{"Balance", same}]

  defp figures(to_date, after_booked),
    do: [{"Balance without booked leave", to_date}, {"Balance with booked leave", after_booked}]

  defp expiring(nil, _leave_type), do: []

  defp expiring(statement, leave_type) do
    for %{expires_on: %Date{} = date} = lot <- statement.lots,
        do: %{amount: Wording.figure(lot.amount, leave_type.unit), expires: Wording.date(date)}
  end

  # A type with no statement has had nothing happen in it, so there is no history to tell.
  defp history(nil, _balance?, _reading), do: nil

  # A type that is recorded only has no balance to show, so its history is the leave taken alone.
  defp history(statement, balance?, reading) do
    history = Ledger.history(reading.person, statement, reading.year)
    %{leave_type: leave_type} = statement

    %{
      span: "#{Wording.date(history.dates.first)} – #{Wording.date(history.dates.last)}",
      earlier: step(history.previous, leave_type, reading),
      later: step(history.next, leave_type, reading),
      earned: earned(history.granted?),
      opening: opening(history.brought_in),
      brought_forward: balance(history.brought_forward, balance?),
      chart: chart(history, leave_type.unit, balance?),
      months: Enum.map(history.months, &month(&1, history, leave_type.unit, balance?))
    }
  end

  defp step(nil, _leave_type, _reading), do: nil

  defp step(year, leave_type, reading),
    do: path(reading.person, reading.mine?, leave_type.id, reading.as_at, year)

  defp opening(nil), do: "Carried forward"
  defp opening(date), do: "Opening balance, #{Wording.date(date)}"

  defp earned(true), do: "Granted"
  defp earned(false), do: "Earned"

  defp note(true), do: "booked"
  defp note(false), do: nil

  defp balance(_amount, false), do: nil
  defp balance(amount, true), do: Wording.number(amount)

  defp month(month, history, unit, balance?) do
    %{
      id: "month-#{month.dates.first}",
      name: Wording.month(month.dates.first, history.dates.first),
      note: note(month.booked?),
      figures: for(column <- @columns, do: moved(month[column])),
      balance: balance(month.balance, balance?),
      lines: Enum.map(month.lines, &line(&1, unit))
    }
  end

  defp moved(amount), do: unless(Decimal.equal?(amount, 0), do: Wording.number(amount))

  defp line(line, unit) do
    %{
      dates: Wording.within_year(line.dates),
      what: what(line, unit),
      figures: for(column <- @columns, do: if(column == line.column, do: moved(line.amount)))
    }
  end

  # Leave counted in days says how many in its figure already.
  defp what(%{days: days} = line, unit) when days == nil or unit == :days, do: @kinds[line.kind]

  defp what(line, :hours),
    do: "#{@kinds[line.kind]}, #{Wording.figure(Decimal.new(line.days), :days)}"

  defp chart(_history, _unit, false), do: nil

  defp chart(history, unit, true) do
    %{dates: dates, chart: chart} = history
    figures = Enum.map(chart.balance ++ chart.booked, &elem(&1, 1))
    place = Chart.placing(dates.first, dates.last, figures)
    x = &elem(place.({&1, Decimal.new(0)}), 0)
    {_x, zero} = place.({dates.first, Decimal.new(0)})

    %{
      label: "Balance from #{Wording.date(dates.first)} to #{Wording.date(dates.last)}",
      zero: zero,
      months: for(month <- 1..11, do: x.(Date.shift(dates.first, month: month))),
      balance: Chart.points(chart.balance, place),
      booked: Chart.points(chart.booked, place),
      losses: Enum.map(chart.losses, &loss(&1, place, unit)),
      as_at: marker(chart.as_at, x),
      from: Wording.brief_date(dates.first),
      to: Wording.brief_date(dates.last)
    }
  end

  defp loss(loss, place, unit) do
    {x, y} = place.({loss.at, loss.balance})
    lost = Wording.figure(Decimal.abs(loss.amount), unit)

    label = "#{lost} #{String.downcase(@kinds[loss.kind])} on #{Wording.date(loss.date)}"

    %{x: x, y: y, label: label, label_x: Chart.label_x(x)}
  end

  defp marker(nil, _x), do: nil
  defp marker(as_at, x), do: %{x: x.(as_at), label: "As at #{Wording.day_and_month(as_at)}"}

  defp nothing([], ready?, true), do: Wording.no_balance(ready?, "you")
  defp nothing([], ready?, false), do: Wording.no_balance(ready?, "they")
  defp nothing(_accounts, _ready?, _mine?), do: nil

  defp path(person, mine?, id, as_at, year \\ nil) do
    query = Enum.reject([as_at: to_string(as_at), year: year], &is_nil(elem(&1, 1)))

    route(person, mine?, id, query)
  end

  defp route(_person, true, nil, query), do: ~p"/balances?#{query}"
  defp route(person, false, nil, query), do: ~p"/people/#{person}/balances?#{query}"
  defp route(_person, true, id, query), do: ~p"/balances/#{id}?#{query}"
  defp route(person, false, id, query), do: ~p"/people/#{person}/balances/#{id}?#{query}"

  defp year(entered) when is_binary(entered) do
    case Integer.parse(entered) do
      {year, ""} -> year
      _not_a_year -> nil
    end
  end

  defp year(_entered), do: nil

  defp as_at(entered, viewer) when is_binary(entered) do
    case Date.from_iso8601(entered) do
      {:ok, date} -> date
      {:error, _reason} -> People.today(viewer)
    end
  end

  defp as_at(_entered, viewer), do: People.today(viewer)
end
