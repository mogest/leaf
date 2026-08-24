defmodule LeafWeb.AtAGlanceLive do
  @moduledoc """
  At a glance: when you are away, how much you have, and what came of what you asked for.

  The three are one question — where your leave is currently at — so they are one page. The
  wording is worked out here and rendered as it stands, so that nothing is decided in the markup.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave
  alias Leaf.Ledger
  alias Leaf.People

  @months 3

  # How many requests the page shows. The sentence under them says so in words.
  @shown 5

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    person = socket.assigns.current_person
    today = People.today(person)
    from = from(params["from"], today)
    {shown, rest} = person |> Leave.requests_undecided_first() |> Enum.split(@shown)
    manager = manager(person)

    {:ok,
     socket
     |> assign(:page_title, "At a glance")
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
    <Layouts.app flash={@flash} page="at-a-glance" viewer={@viewer}>
      <header>
        <h1>At a glance</h1>
        <.link class="button" navigate={~p"/leave/new"}>Request leave</.link>
      </header>

      <div>
        <Parts.calendar months={@months} today={@today} earlier={@earlier} later={@later} />

        <Parts.requests requests={@requests} title="Requests">
          <:empty>You have not asked for any leave yet.</:empty>
          <:footer :if={@more?}>
            Showing five. <.link navigate={~p"/leave"}>See all {@filed}</.link>.
          </:footer>
        </Parts.requests>
      </div>

      <Parts.balance_sheet balances={@balances} title="Balances" path={~p"/balances"} />
    </Layouts.app>
    """
  end

  defp from(named, today) when is_binary(named) do
    case Date.from_iso8601("#{named}-01") do
      {:ok, date} -> date
      {:error, _reason} -> Date.beginning_of_month(today)
    end
  end

  defp from(_named, today), do: Date.beginning_of_month(today)

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
  # A type they hold nothing in and are waiting on nothing from is not their business, and is
  # left off.
  defp balances(person, today) do
    case Ledger.ready?(person, today) do
      true ->
        awaiting = Ledger.awaiting(person)

        person
        |> Ledger.statements(today)
        |> Enum.reject(&nothing?(&1, awaiting))
        |> Enum.map(&balance(&1, awaiting))

      false ->
        []
    end
  end

  defp nothing?(statement, awaiting) do
    Decimal.equal?(statement.balance, 0) and not Map.has_key?(awaiting, statement.leave_type.id)
  end

  defp balance(statement, awaiting) do
    Map.put(Wording.held(statement, awaiting), :path, ~p"/balances/#{statement.leave_type}")
  end
end
