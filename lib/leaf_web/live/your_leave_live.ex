defmodule LeafWeb.YourLeaveLive do
  @moduledoc """
  Your leave: when you are away, how much you have, and what came of what you asked for.

  The three are one question — where your leave is currently at — so they are one page. The
  wording is worked out here and rendered as it stands, so that nothing is decided in the markup.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave
  alias Leaf.Ledger
  alias Leaf.Ledger.Lot
  alias Leaf.People

  @months 3

  # How many requests the page shows. The sentence under them says so in words.
  @shown 4

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    person = socket.assigns.current_person
    today = Date.utc_today()
    from = from(params["from"], today)
    {shown, rest} = person |> Leave.requests() |> Enum.split(@shown)
    manager = manager(person)

    {:ok,
     socket
     |> assign(:page_title, "Your leave")
     |> assign(:today, today)
     |> assign(:earlier, step(from, -@months))
     |> assign(:later, step(from, @months))
     |> assign(:months, Leave.calendar(person, Date.range(from, closes(from))))
     |> assign(:balances, Enum.map(Ledger.statements(person, today), &balance(&1, today)))
     |> assign(:requests, Enum.map(shown, &request(&1, today, manager)))
     |> assign(:filed, length(shown) + length(rest))
     |> assign(:more?, rest != [])}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="your-leave" current_person={@current_person}>
      <header>
        <h1>Your leave</h1>
        <a class="button" href="#">Request leave</a>
      </header>

      <div>
        <Parts.calendar months={@months} today={@today} earlier={@earlier} later={@later} />

        <section class="requests">
          <header>
            <h2>Requests</h2>
          </header>
          <ol :if={@requests != []}>
            <li :for={request <- @requests}>
              <p>
                <span>{request.dates}</span>
                <span>{request.amount}</span>
                <span class="standing" data-standing={request.standing}>{request.label}</span>
              </p>
              <p>{request.detail}</p>
            </li>
          </ol>
          <p :if={@requests == []}>You have not asked for any leave yet.</p>
          <p :if={@more?}>Showing your four most recent. <a href="#">See all {@filed}</a>.</p>
        </section>
      </div>

      <section class="balances">
        <header>
          <h2>Balances</h2>
          <p>as at today</p>
        </header>
        <dl>
          <%= for balance <- @balances do %>
            <dt>{balance.name}</dt>
            <dd>{balance.amount} <small>{balance.unit}</small></dd>
            <dd :if={balance.expiry}>{balance.expiry}</dd>
          <% end %>
        </dl>
      </section>
    </Layouts.app>
    """
  end

  defp from(nil, today), do: Date.beginning_of_month(today)

  defp from(named, today) do
    case Date.from_iso8601("#{named}-01") do
      {:ok, date} -> date
      {:error, _reason} -> Date.beginning_of_month(today)
    end
  end

  defp closes(from), do: from |> Date.shift(month: @months - 1) |> Date.end_of_month()

  defp step(from, months) do
    named = from |> Date.shift(month: months) |> Calendar.strftime("%Y-%m")

    ~p"/?from=#{named}"
  end

  defp manager(person) do
    case People.fetch_manager(person) do
      {:ok, manager} -> manager.name
      :error -> nil
    end
  end

  defp balance(statement, today) do
    %{
      name: statement.leave_type.name,
      amount: number(statement.balance),
      unit: unit(statement.balance, statement.leave_type.unit),
      expiry: expiry(statement, today)
    }
  end

  # What is going to happen to the balance, and nothing at all where nothing is. The soonest lot
  # to lapse is the one worth saying; one that is the whole balance says so without the figure.
  defp expiry(statement, today) do
    case statement.lots |> Lot.soonest_first() |> List.first() do
      %{expires_on: nil} -> nil
      nil -> nil
      lot -> lapsing(lot, statement, today)
    end
  end

  defp lapsing(lot, statement, today) do
    date = lapse_date(lot.expires_on, today)

    case Decimal.equal?(lot.amount, statement.balance) do
      true -> "Expires #{date}"
      false -> "#{figure(lot.amount, statement.leave_type.unit)} #{expire(lot.amount)} on #{date}"
    end
  end

  defp expire(amount) do
    case Decimal.equal?(amount, 1) do
      true -> "expires"
      false -> "expire"
    end
  end

  # Within the week, the day it falls on is what somebody acts on rather than the date.
  defp lapse_date(date, today) do
    case Date.diff(date, today) < 7 do
      true -> long(date)
      false -> Calendar.strftime(date, "%-d %B")
    end
  end

  defp request(request, today, manager) do
    standing = standing(request, today)

    %{
      dates: dates(request),
      amount: amount(request),
      standing: standing,
      label: standing |> Atom.to_string() |> String.capitalize(),
      detail: "#{types(request)} · #{progress(request, manager)}"
    }
  end

  # Leave that has already happened is a different thing to read from leave still to come.
  defp standing(%{status: :approved} = request, today), do: taken(last(request), today)
  defp standing(request, _today), do: request.status

  defp taken(last, today) do
    case Date.before?(last, today) do
      true -> :taken
      false -> :approved
    end
  end

  defp dates(request) do
    dates = Enum.map(request.days, & &1.date)

    span(Enum.min(dates, Date), Enum.max(dates, Date))
  end

  defp span(date, date), do: long(date)

  defp span(first, last) do
    case {first.year, first.month} == {last.year, last.month} do
      true -> "#{Calendar.strftime(first, "%A %-d")} – #{long(last)}"
      false -> "#{long(first)} – #{long(last)}"
    end
  end

  defp last(request), do: request.days |> Enum.map(& &1.date) |> Enum.max(Date)

  defp long(date), do: Calendar.strftime(date, "%A %-d %B")

  # A request can be asked for in both units at once, and each is only worth what it says it is:
  # what a day off comes to in hours follows from the date, not from the request.
  defp amount(request) do
    request.days
    |> Enum.group_by(& &1.unit, & &1.amount)
    |> Enum.map_join(" and ", fn {unit, amounts} -> figure(total(amounts), unit) end)
  end

  defp total(amounts), do: Enum.reduce(amounts, &Decimal.add/2)

  defp types(request) do
    [first | rest] = request.days |> Enum.map(& &1.leave_type.name) |> Enum.uniq()

    joined([first | Enum.map(rest, &String.downcase/1)])
  end

  defp joined([name]), do: name

  defp joined(names) do
    {leading, [last]} = Enum.split(names, -1)

    "#{Enum.join(leading, ", ")} and #{last}"
  end

  defp progress(%{status: :pending} = request, nil), do: "sent on #{on(request.inserted_at)}"

  defp progress(%{status: :pending} = request, manager) do
    "sent to #{manager} on #{on(request.inserted_at)}"
  end

  defp progress(%{status: :declined, review_comment: nil} = request, _manager) do
    "declined by #{request.reviewed_by.name} on #{on(request.reviewed_at)}"
  end

  defp progress(%{status: :declined} = request, _manager) do
    "#{request.reviewed_by.name} said #{request.review_comment}"
  end

  defp progress(request, _manager) do
    "#{request.status} by #{request.reviewed_by.name} on #{on(request.reviewed_at)}"
  end

  defp on(at), do: Calendar.strftime(at, "%-d %B")

  defp figure(amount, unit), do: "#{number(amount)} #{unit(amount, unit)}"

  # Rounded where it is shown and nowhere before it, and with nothing trailing: 33, not 33.00.
  defp number(amount) do
    amount |> Decimal.round(2) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  defp unit(amount, unit), do: named(unit, Decimal.equal?(amount, 1))

  defp named(:hours, true), do: "hour"
  defp named(:hours, false), do: "hours"
  defp named(:days, true), do: "day"
  defp named(:days, false), do: "days"
end
