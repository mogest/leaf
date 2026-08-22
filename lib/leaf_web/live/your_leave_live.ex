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
     |> assign(:balances, balances(person, today))
     |> assign(:requests, Enum.map(shown, &Wording.filed(&1, today, manager)))
     |> assign(:filed, length(shown) + length(rest))
     |> assign(:more?, rest != [])}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="your-leave" current_person={@current_person}>
      <header>
        <h1>Your leave</h1>
        <.link class="button" navigate={~p"/leave/new"}>Request leave</.link>
      </header>

      <div>
        <Parts.calendar months={@months} today={@today} earlier={@earlier} later={@later} />

        <Parts.requests requests={@requests}>
          <:empty>You have not asked for any leave yet.</:empty>
          <:footer :if={@more?}>
            Showing your four most recent. <.link navigate={~p"/leave"}>See all {@filed}</.link>.
          </:footer>
        </Parts.requests>
      </div>

      <section class="balances">
        <header>
          <h2>Balances</h2>
          <p>as at today</p>
        </header>
        <dl>
          <%= for balance <- @balances do %>
            <dt><.link navigate={balance.ledger}>{balance.name}</.link></dt>
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

  # A balance is worked out from the whole of somebody's record, so half a record has none to show.
  defp balances(person, today) do
    case Ledger.ready?(person, today) do
      true -> person |> Ledger.statements(today) |> Enum.map(&balance(&1, person, today))
      false -> []
    end
  end

  defp balance(statement, person, today) do
    %{
      name: statement.leave_type.name,
      amount: Wording.number(statement.balance),
      unit: Wording.unit(statement.balance, statement.leave_type.unit),
      expiry: expiry(statement, today),
      ledger: ~p"/people/#{person}/balances/#{statement.leave_type}"
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
      false -> "#{figure(lot, statement)} #{expire(lot.amount)} on #{date}"
    end
  end

  defp figure(lot, statement), do: Wording.figure(lot.amount, statement.leave_type.unit)

  defp expire(amount) do
    case Decimal.equal?(amount, 1) do
      true -> "expires"
      false -> "expire"
    end
  end

  # Within the week, the day it falls on is what somebody acts on rather than the date.
  defp lapse_date(date, today) do
    case Date.diff(date, today) < 7 do
      true -> Wording.weekday(date)
      false -> Wording.day_and_month(date)
    end
  end
end
