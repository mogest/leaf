defmodule LeafWeb.RequestLeaveLive do
  @moduledoc """
  Asking for leave, and revising what was asked for.

  What is filled in is an instruction — a leave type, a stretch of dates, and how much of the day
  where it is one day — rather than the days themselves, which the work pattern decides: a request
  covers the days in the range the person actually works, and nothing else.

  A stretch of dates is whole days, whatever those days turn out to be worth, and a last day left
  blank asks for the first day on its own. Part of a day is asked of one day and asked in hours,
  because hours are what somebody can count: nobody knows offhand what 0.4 of a nine-hour Wednesday
  is. What the hours draw is the leave type's business rather than the request's, and the balance
  says so — 4.5 hours against sick leave counted in days is half a day of it.

  Amending replaces what a request asks for, so it is the same instruction given again. Days this
  cannot say — a stretch that is not whole days, or more than one leave type — are shown as what
  would replace them, said out loud rather than found out afterwards. A day covered by more than
  one leave type is two requests, each asking for its own part of it.
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
  @role :member
  def handle_event("validate", %{"request" => params}, socket) do
    {:noreply, filled(socket, params)}
  end

  @role :member
  def handle_event("settle", %{"end" => moved}, socket) do
    {:noreply, filled(socket, paired(socket.assigns.form.params, moved))}
  end

  @role :member
  def handle_event("save", %{"request" => params}, socket) do
    {entries, _problems} = asked(socket, params)
    attrs = %{days: entries, note: blank(params["note"])}

    {:noreply, socket |> filled(params) |> saved(file(socket, attrs))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="request-leave" viewer={@viewer}>
      <header>
        <h1>{@title}</h1>
      </header>

      <.form id="request" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Your request</h2>
          </header>
          <.input
            field={@form[:leave_type_id]}
            type="select"
            label="Leave type"
            prompt="Choose one"
            options={@leave_types}
          />
          <div class="paired">
            <.input
              field={@form[:from]}
              type="date"
              label="First day"
              phx-blur="settle"
              phx-patch-focused
              phx-value-end="from"
            />
            <.input
              field={@form[:to]}
              type="date"
              label="Last day"
              phx-blur="settle"
              phx-patch-focused
              phx-value-end="to"
            />
          </div>
          <.input
            :if={@portion}
            field={@form[:amount]}
            type="text"
            label="Hours off"
            placeholder={@portion}
          />
          <.input field={@form[:note]} type="textarea" label="Note" />
        </section>

        <section :if={@filing || @replacing}>
          <header>
            <h2>Day by day</h2>
          </header>
          <table :if={@filing}>
            <thead>
              <tr>
                <th>Date</th>
                <th>Off</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={day <- @filing.days} data-working={day.working}>
                <th>{day.date}</th>
                <td>{day.off}</td>
              </tr>
            </tbody>
            <tfoot>
              <tr>
                <th>Total</th>
                <td>{@filing.total}</td>
              </tr>
            </tfoot>
          </table>
          <dl :if={@filing && @filing.balance}>
            <dt>{@filing.balance.name} left on {@filing.balance.date}</dt>
            <dd data-tone={@filing.balance.tone}>
              {@filing.balance.left} <small>if approved</small>
            </dd>
          </dl>
          <p :if={@replacing}>{@replacing}</p>
        </section>

        <footer>
          <ul :if={@problems != []}>
            <li :for={problem <- @problems}>{problem}</li>
          </ul>
          <button class="button" type="submit" disabled={@entries == []}>{@action}</button>
          <.link navigate={~p"/leave"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp opened(socket, :new, _params, today) do
    socket
    |> assign(:page_title, "Request leave")
    |> assign(:title, "Request leave")
    |> assign(:action, "Send the request")
    |> assign(:done, "Your request is filed.")
    |> assign(:request, nil)
    |> assign(:replaced, false)
    |> holding(socket.assigns.current_person, today)
    |> filled(%{})
  end

  defp opened(socket, :amend, %{"id" => id}, today) do
    {:ok, request} = Leave.fetch_request(id)
    true = Leave.revisable?(request, socket.assigns.current_person)
    {params, replaced} = asked_again(request)

    socket
    |> assign(:page_title, "Edit a request")
    |> assign(:title, "Edit a request")
    |> assign(:action, "Save the change")
    |> assign(:done, "The request is changed.")
    |> assign(:request, request)
    |> assign(:replaced, replaced)
    |> holding(request.person, today)
    |> filled(params)
  end

  # What the person holds now, read once: the balance a type is offered with does not turn on what
  # is typed into the form.
  defp holding(socket, person, today) do
    ready? = Ledger.ready?(person, today)
    held = held(person, today, ready?)
    offered = Leave.requestable(person, Date.range(today, today))

    socket
    |> assign(:person, person)
    |> assign(:ready?, ready?)
    |> assign(:offered, offered)
    |> assign(:leave_types, Enum.map(offered, &{offering(&1, held[&1.id]), &1.id}))
  end

  defp held(_person, _today, false), do: %{}

  defp held(person, today, true) do
    person |> Ledger.statements(today) |> Map.new(&{&1.leave_type.id, &1})
  end

  # A type is offered with what is left in it, so that choosing one is not a guess.
  defp offering(leave_type, nil), do: leave_type.name

  defp offering(leave_type, statement) do
    "#{leave_type.name} — #{remaining(statement.balance, leave_type.unit)}"
  end

  defp remaining(balance, unit) do
    case Decimal.negative?(balance) do
      true -> "#{Wording.figure(Decimal.abs(balance), unit)} overdrawn"
      false -> "#{Wording.figure(balance, unit)} left"
    end
  end

  # An amendment starts from what the request already says: the span its days cover, the type of
  # the first, and what they ask for where this can ask for it too.
  defp asked_again(request) do
    [first | _rest] = days = Enum.sort_by(request.days, & &1.date, Date)
    {amount, replaced} = sayable(days)

    {%{
       "leave_type_id" => first.leave_type_id,
       "from" => to_string(first.date),
       "to" => to_string(List.last(days).date),
       "amount" => amount,
       "note" => request.note
     }, replaced}
  end

  # What the days ask for as this form would ask for it, and whether there is no saying it: hours
  # off one day, or a stretch of whole days, and one leave type across the lot of them.
  defp sayable(days) do
    case Enum.uniq_by(days, & &1.leave_type_id) do
      [_one] -> said(days)
      _several -> {"", true}
    end
  end

  defp said([%{unit: :hours} = day]), do: {Wording.number(day.amount), false}
  defp said(days), do: blank_for(Enum.all?(days, &whole?/1))

  defp whole?(%{unit: :days, amount: amount}), do: Decimal.equal?(amount, 1)
  defp whole?(_day), do: false

  # A blank is the whole day, so it stands for days that are all whole days and for nothing else.
  defp blank_for(true), do: {"", false}
  defp blank_for(false), do: {"", true}

  # The two dates are one span, so each end minds the other: the end just left fills in a blank
  # other end and drags an other end that is the wrong side of it. This is settled on the way out of
  # a field and not on every change, because a date picker walked back through the months writes a
  # date at each month it passes, and none of them is a day anybody has asked for.
  defp paired(params, moved) do
    other = other(moved)

    case {blank(params[moved]), blank(params[other])} do
      {nil, _kept} -> params
      {entered, nil} -> Map.put(params, other, entered)
      {entered, kept} -> Map.put(params, other, ordered(moved, entered, kept))
    end
  end

  defp other("from"), do: "to"
  defp other("to"), do: "from"

  defp ordered("from", entered, kept), do: max(entered, kept)
  defp ordered("to", entered, kept), do: min(entered, kept)

  defp filled(socket, params) do
    {entries, problems} = asked(socket, params)

    socket
    |> assign(:form, to_form(params, as: :request))
    |> assign(:entries, entries)
    |> assign(:problems, problems)
    |> assign(:portion, portion(socket, params))
    |> assign(:filing, filing(socket, params, entries))
    |> assign(:replacing, replacing(socket.assigns.replaced, entries))
  end

  # Part of a day can only be asked of one day, so the field is there for one date and gone for a
  # stretch. It turns on the dates alone and not on what has been typed into it, so that a half
  # finished number cannot take the field out from under whoever is typing it.
  defp portion(socket, params) do
    case range(params["from"], params["to"]) do
      {:ok, %{first: date, last: date}} -> whole_day(socket.assigns.person, date)
      _stretch_or_neither -> nil
    end
  end

  # The whole day the field would replace is named in it, so that nothing has to be worked out to
  # fill it in and no fraction has to be trusted.
  defp whole_day(person, date) do
    case Leave.working_days(person, Date.range(date, date)) do
      [{_date, hours}] -> "the whole day (#{Wording.figure(hours, :hours)})"
      [] -> "the whole day"
    end
  end

  # Amending days this cannot say replaces them, so what that costs is said where it will be read.
  defp replacing(true, [_first | _rest]) do
    "Those days do not all ask for the whole day. Saving this replaces what they ask for."
  end

  defp replacing(_replaced, _entries), do: nil

  # What will be filed, a row for every date the stretch covers rather than for every date it
  # draws on: a count of working days shorter than the stretch asked for is otherwise a mistake
  # nobody can see the reason for. What decides there is a table is the stretch and not what it
  # comes to, so asking for a week that holds one working day still shows the week.
  defp filing(_socket, _params, []), do: nil

  defp filing(socket, params, entries) do
    {:ok, span} = range(params["from"], params["to"])

    spanned(socket, span, entries)
  end

  # One date has no rows worth reading — it is the field above and the hours beside it.
  defp spanned(_socket, %Date.Range{first: date, last: date}, _entries), do: nil

  defp spanned(socket, span, entries) do
    worked = Map.new(Leave.working_days(socket.assigns.person, span))

    %{
      days: Enum.map(span, &day(&1, worked[&1])),
      total: total(entries),
      balance: moving(projection(socket, entries))
    }
  end

  # A day off is the hours in it, which is what a whole day of somebody's own is worth and not what
  # a day is worth. What it draws is the total's business: every one of these rows would say the
  # same "1 day" as the last.
  defp day(date, nil), do: %{date: Wording.brief(date), off: "not worked", working: "no"}

  defp day(date, hours) do
    %{date: Wording.brief(date), off: Wording.figure(hours, :hours), working: nil}
  end

  defp total(entries) do
    entries
    |> Enum.map(& &1.amount)
    |> Enum.reduce(&Decimal.add/2)
    |> Wording.figure(hd(entries).unit)
  end

  # What is asked for, and whatever about the instruction stops it being answerable. Nothing
  # chosen is not a problem to report, it is a form nobody has filled in yet.
  defp asked(socket, params) do
    with {:ok, leave_type} <- chosen(socket, params["leave_type_id"]),
         {:ok, range} <- range(params["from"], params["to"]),
         {:ok, days} <- workable(Leave.working_days(socket.assigns.person, range), range),
         {:ok, amount, unit} <- asked_for(params["amount"], days),
         entries = Enum.map(days, &entry(&1, leave_type, amount, unit)),
         :ok <- free(socket, entries) do
      {entries, []}
    else
      :none -> {[], []}
      {:error, problems} -> {[], List.wrap(problems)}
    end
  end

  defp chosen(socket, id) do
    case offered(socket, id) do
      nil -> :none
      leave_type -> {:ok, leave_type}
    end
  end

  defp offered(socket, id), do: Enum.find(socket.assigns.offered, &(&1.id == id))

  # One date names itself, the way the hours in a day do. A stretch cannot without listing a
  # weekend back at somebody who can see it is a weekend.
  defp workable([], %Date.Range{first: date, last: date}) do
    {:error, "You do not work on #{Wording.weekday(date)}."}
  end

  defp workable([], _range), do: {:error, "You do not work on any of those days."}
  defp workable(days, _range), do: {:ok, days}

  defp entry({date, _hours}, leave_type, amount, unit) do
    %{leave_type_id: leave_type.id, date: date, amount: amount, unit: unit}
  end

  # A blank end is the end that was entered: one date is a day off, not half of a stretch, and
  # somebody still in the first field has not left the last one out.
  defp range(from, to) do
    with {:ok, first} <- on(blank(from) || to, "first day"),
         {:ok, last} <- on(blank(to) || from, "last day") do
      bounded(first, last)
    end
  end

  defp bounded(first, last) do
    case Date.after?(first, last) do
      true -> {:error, "The last day comes before the first."}
      false -> {:ok, Date.range(first, last)}
    end
  end

  # A date nobody has entered yet is not a refusal to report, it is a field they have not reached.
  defp on(blank, _what) when blank in [nil, ""], do: :none

  defp on(entered, what) do
    case Date.from_iso8601(entered) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, "Give a #{what}."}
    end
  end

  # A blank asks for the whole of each day, which is a day whatever the leave type counts in. Hours
  # are a thing about one day: a stretch has no one day to take them out of.
  defp asked_for(blank, _days) when blank in [nil, ""], do: {:ok, Decimal.new(1), :days}

  defp asked_for(_entered, [_first, _second | _rest]) do
    {:error, "Hours off can only be asked of a single day."}
  end

  defp asked_for(entered, _day) do
    case Decimal.parse(String.trim(entered)) do
      {amount, ""} -> positive(amount)
      _unparsed -> {:error, "The hours off have to be a number."}
    end
  end

  defp positive(amount) do
    case Decimal.positive?(amount) do
      true -> {:ok, amount, :hours}
      false -> {:error, "The hours off have to be more than nothing."}
    end
  end

  # A day off is at most what is left of the day: the hours worked on it, less the leave already
  # filed into it. Every date that will not fit is named, because fixing the first would otherwise
  # only turn up the next.
  defp free(socket, entries) do
    case Leave.clashes(socket.assigns.person, Leave.proposed(entries), socket.assigns.request) do
      [] -> :ok
      clashes -> {:error, Enum.map(clashes, &spoken_for/1)}
    end
  end

  defp spoken_for({date, free}) do
    case Decimal.positive?(free) do
      true -> "#{Wording.weekday(date)} has only #{Wording.figure(free, :hours)} free."
      false -> "You already have leave on #{Wording.weekday(date)}."
    end
  end

  # An approved request has nothing to project against: what it already draws is counted, so
  # adding what it would draw instead would count it twice over.
  defp projection(%{assigns: %{request: %{status: status}}}, _entries) when status != :pending,
    do: nil

  defp projection(%{assigns: %{ready?: false}}, _entries), do: nil

  defp projection(socket, [entry | _rest] = entries) do
    %{person: person, today: today} = socket.assigns

    case Ledger.fetch_statement(person, entry.leave_type_id, today, Leave.proposed(entries)) do
      {:ok, statement} -> statement
      :error -> nil
    end
  end

  # One leave type is asked for, so one balance is left: it is a line under the table rather than a
  # row in it, because what is left afterwards is not one of the days being filed. What the leave
  # draws is the table's own total, which is why the figure it came off is not shown beside it.
  defp moving(nil), do: nil

  defp moving(statement) do
    %{
      name: statement.leave_type.name,
      date: Wording.date(statement.as_at),
      left: Wording.figure(statement.balance, statement.leave_type.unit),
      tone: tone(statement.balance)
    }
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

  defp blank(note) when note in [nil, ""], do: nil
  defp blank(note), do: note
end
