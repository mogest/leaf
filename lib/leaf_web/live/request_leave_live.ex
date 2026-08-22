defmodule LeafWeb.RequestLeaveLive do
  @moduledoc """
  Asking for leave, and revising what was asked for.

  What is filled in is an instruction — a leave type, a stretch of dates, and how much of each day
  — rather than the days themselves, which the work pattern decides: a request covers the days in
  the range the person actually works, and nothing else. Leaving the amount blank asks for the
  whole of each of them, whatever those days turn out to be worth.

  Amending replaces what a request asks for, so it is the same instruction given again. A day
  covered by more than one leave type is two requests, each asking for its own part of it.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave
  alias Leaf.Ledger

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    today = Date.utc_today()

    {:ok, socket |> assign(:today, today) |> opened(socket.assigns.live_action, params, today)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"request" => params}, socket) do
    {:noreply, filled(socket, params)}
  end

  def handle_event("save", %{"request" => params}, socket) do
    {entries, _problems} = asked(socket.assigns.person, params)
    attrs = %{days: entries, note: blank(params["note"])}

    {:noreply, socket |> filled(params) |> saved(file(socket, attrs))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="request-leave" current_person={@current_person}>
      <header>
        <h1>{@title}</h1>
        <.link navigate={~p"/leave"}>Your requests</.link>
      </header>

      <.form id="request" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>What you are asking for</h2>
          </header>
          <.input
            field={@form[:leave_type_id]}
            type="select"
            label="Leave type"
            prompt="Choose one"
            options={@leave_types}
          />
          <.input field={@form[:from]} type="date" label="First day" />
          <.input field={@form[:to]} type="date" label="Last day" />
          <.input
            field={@form[:amount]}
            type="text"
            label="Amount per day"
            placeholder="the whole day"
          />
          <.input field={@form[:unit]} type="select" label="Counted in" options={@units} />
          <.input field={@form[:note]} type="textarea" label="Note" />
        </section>

        <section>
          <header>
            <h2>What will be filed</h2>
            <p :if={@covering}>{@covering}</p>
          </header>
          <ol :if={@lines != []}>
            <li :for={line <- @lines}>
              <span>{line.date}</span>
              <span>{line.leave_type}</span>
              <span>{line.amount}</span>
            </li>
          </ol>
          <p :if={@lines == []}>{@nothing}</p>
          <ul :if={@problems != []}>
            <li :for={problem <- @problems} data-tone="wrong">{problem}</li>
          </ul>
        </section>

        <section :if={@projection}>
          <header>
            <h2>Balances if it is approved</h2>
          </header>
          <ol>
            <li :for={balance <- @projection} data-tone={balance.tone}>
              <span>{balance.name}</span>
              <span>{balance.change}</span>
              <span>{balance.amount}</span>
            </li>
          </ol>
        </section>

        <footer>
          <button class="button" type="submit" disabled={@lines == []}>{@action}</button>
          <.link navigate={~p"/leave"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp opened(socket, :new, _params, today) do
    person = socket.assigns.current_person

    socket
    |> assign(:page_title, "Request leave")
    |> assign(:title, "Request leave")
    |> assign(:action, "Send the request")
    |> assign(:done, "Your request is filed.")
    |> assign(:person, person)
    |> assign(:request, nil)
    |> assign(:leave_types, choices(person, today))
    |> assign(:units, units())
    |> filled(%{"from" => to_string(today), "to" => to_string(today), "unit" => "hours"})
  end

  defp opened(socket, :amend, %{"id" => id}, today) do
    {:ok, request} = Leave.fetch_request(id)
    true = Leave.revisable?(request, socket.assigns.current_person)

    socket
    |> assign(:page_title, "Amend a request")
    |> assign(:title, "Amend a request")
    |> assign(:action, "Save the change")
    |> assign(:done, "The request is changed.")
    |> assign(:person, request.person)
    |> assign(:request, request)
    |> assign(:leave_types, choices(request.person, today))
    |> assign(:units, units())
    |> filled(asked_again(request))
  end

  # An amendment starts from what the request already says. Its days can be anything at all, so
  # what comes back is the instruction that would produce them: the span they cover, the type of
  # the first, and an amount only where every day asks for the same one.
  defp asked_again(request) do
    [first | _rest] = days = Enum.sort_by(request.days, & &1.date, Date)

    %{
      "leave_type_id" => first.leave_type_id,
      "from" => to_string(first.date),
      "to" => to_string(List.last(days).date),
      "amount" => uniform(days),
      "unit" => to_string(first.unit),
      "note" => request.note
    }
  end

  defp uniform(days) do
    case days |> Enum.map(&{&1.amount, &1.unit}) |> Enum.uniq() do
      [{amount, :days}] -> whole_day(amount)
      [{amount, :hours}] -> Wording.number(amount)
      _mixed -> ""
    end
  end

  defp whole_day(amount) do
    case Decimal.equal?(amount, 1) do
      true -> ""
      false -> Wording.number(amount)
    end
  end

  defp filled(socket, params) do
    person = socket.assigns.person
    {entries, problems} = asked(person, params)
    lines = Enum.map(entries, &line(&1, socket.assigns.leave_types))

    socket
    |> assign(:form, to_form(params, as: :request))
    |> assign(:lines, lines)
    |> assign(:problems, problems)
    |> assign(:covering, covering(lines))
    |> assign(:nothing, nothing(problems))
    |> assign(:projection, projection(socket, person, entries))
  end

  defp covering([]), do: nil
  defp covering([_line]), do: "one working day"
  defp covering(lines), do: "#{length(lines)} working days"

  defp nothing([]), do: "Nothing yet — choose a leave type and the days you want off."
  defp nothing(_problems), do: "Nothing can be filed as it stands."

  defp line(entry, leave_types) do
    %{
      date: Wording.weekday(entry.date),
      amount: Wording.figure(entry.amount, entry.unit),
      leave_type: named(leave_types, entry.leave_type_id)
    }
  end

  defp named(leave_types, id) do
    Enum.find_value(leave_types, "", fn {name, value} -> value == id && name end)
  end

  # What is asked for, and everything about the instruction that stops it being answerable. A
  # blank amount asks for the whole of each day, which is a day whatever the leave type counts in.
  defp asked(person, params) do
    with {:ok, leave_type_id} <- chosen(params["leave_type_id"]),
         {:ok, range} <- range(params["from"], params["to"]),
         {:ok, amount, unit} <- per_day(params["amount"], params["unit"]) do
      person
      |> Leave.working_days(range)
      |> Enum.map(&entry(&1, leave_type_id, amount, unit))
      |> answered()
    else
      {:error, problem} -> {[], [problem]}
    end
  end

  defp answered([]), do: {[], ["Not one of those dates is a day you work."]}
  defp answered(entries), do: {entries, []}

  defp entry({date, _hours}, leave_type_id, amount, unit) do
    %{leave_type_id: leave_type_id, date: date, amount: amount, unit: unit}
  end

  defp chosen(id) when id in [nil, ""], do: {:error, "Choose a leave type."}
  defp chosen(leave_type_id), do: {:ok, leave_type_id}

  defp range(from, to) do
    with {:ok, first} <- on(from, "first day"),
         {:ok, last} <- on(to, "last day") do
      bounded(first, last)
    end
  end

  defp bounded(first, last) do
    case Date.after?(first, last) do
      true -> {:error, "The last day comes before the first."}
      false -> {:ok, Date.range(first, last)}
    end
  end

  defp on(entered, what) do
    case Date.from_iso8601(to_string(entered)) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, "Give a #{what}."}
    end
  end

  defp per_day(blank, _unit) when blank in [nil, ""], do: {:ok, Decimal.new(1), :days}

  defp per_day(entered, unit) do
    case Decimal.parse(String.trim(entered)) do
      {amount, ""} -> positive(amount, unit)
      _unparsed -> {:error, "The amount per day has to be a number."}
    end
  end

  defp positive(amount, unit) do
    case Decimal.positive?(amount) do
      true -> {:ok, amount, counted_in(unit)}
      false -> {:error, "The amount per day has to be more than nothing."}
    end
  end

  defp counted_in("days"), do: :days
  defp counted_in(_hours), do: :hours

  # An approved request has nothing to project against: what it already draws is counted, so
  # adding what it would draw instead would count it twice over.
  defp projection(%{assigns: %{request: %{status: status}}}, _person, _entries)
       when status != :pending,
       do: nil

  defp projection(_socket, _person, []), do: nil

  defp projection(socket, person, entries) do
    case Ledger.ready?(person, socket.assigns.today) do
      true -> projected(person, socket.assigns.today, entries)
      false -> nil
    end
  end

  defp projected(person, today, entries) do
    held = person |> Ledger.statements(today) |> Map.new(&{&1.leave_type.id, &1})

    person
    |> Ledger.statements(today, Leave.proposed(entries))
    |> Enum.map(&balance(&1, held[&1.leave_type.id]))
  end

  defp balance(statement, held) do
    %{
      name: statement.leave_type.name,
      amount: Wording.figure(statement.balance, statement.leave_type.unit),
      change: change(statement, held),
      tone: tone(statement.balance)
    }
  end

  defp change(_statement, nil), do: "all of it"

  defp change(statement, held) do
    case Decimal.sub(statement.balance, held.balance) do
      %Decimal{coef: 0} -> nil
      moved -> "#{Wording.number(moved)} from #{Wording.number(held.balance)}"
    end
  end

  defp tone(balance) do
    case Decimal.negative?(balance) do
      true -> "wrong"
      false -> nil
    end
  end

  defp file(%{assigns: %{request: nil}} = socket, attrs) do
    Leave.request(socket.assigns.person, socket.assigns.current_person, attrs)
  end

  defp file(socket, attrs) do
    Leave.amend(socket.assigns.request, socket.assigns.current_person, attrs)
  end

  defp saved(socket, {:ok, _request}) do
    socket |> put_flash(:info, socket.assigns.done) |> push_navigate(to: ~p"/leave")
  end

  defp saved(socket, {:error, :forbidden}) do
    put_flash(socket, :error, "That is not yours to change.")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :problems, refused(changeset))
  end

  # A refusal from the write path is about a day rather than about a field somebody filled in, so
  # it is said alongside the days rather than under an input nobody typed into.
  defp refused(changeset) do
    changeset |> Ecto.Changeset.traverse_errors(&translate_error/1) |> flatten()
  end

  defp flatten(errors) when is_map(errors) do
    Enum.flat_map(errors, fn {field, messages} -> flatten(field, messages) end)
  end

  defp flatten(field, [message | _rest] = messages) when is_binary(message) do
    Enum.map(messages, &"#{plainly(field)} #{&1}")
  end

  defp flatten(_field, nested) when is_list(nested), do: Enum.flat_map(nested, &flatten/1)
  defp flatten(_field, nested), do: flatten(nested)

  defp plainly(field) do
    field |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp choices(person, today) do
    person
    |> Leave.requestable(Date.range(today, today))
    |> Enum.map(&{Wording.leave_type(&1), &1.id})
  end

  defp units, do: [{"hours", "hours"}, {"days", "days"}]

  defp blank(note) when note in [nil, ""], do: nil
  defp blank(note), do: note
end
