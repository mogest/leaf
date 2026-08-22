defmodule LeafWeb.BalanceLive do
  @moduledoc """
  How one balance was arrived at: what is held, and every movement that made it.

  Nothing here is stored — the whole account is worked out from the person's dates, hours, policy
  and the leave they filed — so this page answers "how did this number happen", which is the one
  question the figure on the dashboard cannot answer for itself.
  """

  use LeafWeb, :live_view

  alias Leaf.Ledger
  alias Leaf.People

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
    {:ok, person} = People.fetch_person(params["person_id"])
    as_at = as_at(params["as_at"])

    {:noreply, opened(socket, person, params["leave_type_id"], as_at)}
  end

  @impl Phoenix.LiveView
  def handle_event("as-at", %{"ledger" => %{"as_at" => as_at}}, socket) do
    {:noreply, push_patch(socket, to: here(socket.assigns, as_at))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="balance" current_person={@current_person}>
      <header>
        <h1>{@leave_type.name}</h1>
        <.link :if={@mine?} navigate={~p"/"}>Your leave</.link>
        <.link :if={!@mine?} navigate={~p"/people/#{@person}"}>{@person.name}</.link>
      </header>

      <.form id="as-at" for={@form} phx-change="as-at">
        <.input field={@form[:as_at]} type="date" label="As at" />
      </.form>

      <section class="balances">
        <header>
          <h2>Balance</h2>
          <p>as at {Wording.date(@as_at)}</p>
        </header>
        <dl>
          <dt>Held</dt>
          <dd>{@balance}</dd>
        </dl>
      </section>

      <section>
        <header>
          <h2>Lots held</h2>
          <p>leave draws on whichever lapses soonest</p>
        </header>
        <ol :if={@lots != []}>
          <li :for={lot <- @lots}>
            <span>{lot.amount}</span>
            <span>{lot.expires}</span>
          </li>
        </ol>
        <p :if={@lots == []}>Nothing held.</p>
      </section>

      <section>
        <header>
          <h2>How it was arrived at</h2>
          <p>{@counted}</p>
        </header>
        <table :if={@movements != []}>
          <thead>
            <tr>
              <th scope="col">Date</th>
              <th scope="col">What</th>
              <th scope="col">Amount</th>
              <th scope="col">Lapses</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={movement <- @movements}>
              <td>{movement.date}</td>
              <td>{movement.kind}</td>
              <td data-tone={movement.tone}>{movement.amount}</td>
              <td>{movement.expires}</td>
            </tr>
          </tbody>
        </table>
        <p :if={@movements == []}>Nothing has happened to it yet.</p>
      </section>
    </Layouts.app>
    """
  end

  defp opened(socket, person, leave_type_id, as_at) do
    case People.oversees?(socket.assigns.current_person, person) do
      true -> shown(socket, person, as_at, statement(person, leave_type_id, as_at))
      false -> refused(socket)
    end
  end

  defp refused(socket) do
    socket |> put_flash(:error, "That account is not yours to read.") |> push_navigate(to: ~p"/")
  end

  defp statement(person, leave_type_id, as_at) do
    case Ledger.ready?(person, as_at) do
      true -> Ledger.fetch_statement(person, leave_type_id, as_at)
      false -> :error
    end
  end

  defp shown(socket, person, _as_at, :error) do
    socket
    |> put_flash(:error, "There is no account to show for that.")
    |> push_navigate(to: ~p"/people/#{person}")
  end

  defp shown(socket, person, as_at, {:ok, statement}) do
    socket
    |> assign(:page_title, statement.leave_type.name)
    |> assign(:person, person)
    |> assign(:mine?, person.id == socket.assigns.current_person.id)
    |> assign(:leave_type, statement.leave_type)
    |> assign(:as_at, as_at)
    |> assign(:form, to_form(%{"as_at" => to_string(as_at)}, as: :ledger))
    |> assign(:balance, Wording.figure(statement.balance, statement.leave_type.unit))
    |> assign(:lots, Enum.map(statement.lots, &lot(&1, statement.leave_type)))
    |> assign(:movements, Enum.map(statement.movements, &movement(&1, statement.leave_type)))
    |> assign(:counted, counted(statement.movements))
  end

  defp counted([]), do: "nothing yet"
  defp counted([_one]), do: "one movement"
  defp counted(movements), do: "#{length(movements)} movements"

  defp here(assigns, as_at) do
    ~p"/people/#{assigns.person}/balances/#{assigns.leave_type}?as_at=#{as_at}"
  end

  defp as_at(nil), do: Date.utc_today()

  defp as_at(entered) do
    case Date.from_iso8601(entered) do
      {:ok, date} -> date
      {:error, _reason} -> Date.utc_today()
    end
  end

  defp lot(lot, leave_type) do
    %{amount: Wording.figure(lot.amount, leave_type.unit), expires: lapses(lot.expires_on)}
  end

  defp lapses(nil), do: "does not lapse"
  defp lapses(date), do: "lapses #{Wording.date(date)}"

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
end
