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
  alias Leaf.People

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    today = People.today(socket.assigns.current_person)

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
    socket = filled(socket, params)
    attrs = %{days: socket.assigns.entries, note: socket.assigns.order.note}

    {:noreply, saved(socket, file(socket, attrs))}
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
          <p :if={@replacing}>{@replacing}</p>
        </section>

        <section :if={@balance}>
          <header>
            <h2>What it would leave</h2>
          </header>
          <dl>
            <dt>{@balance.name} left on {@balance.date}</dt>
            <dd data-tone={@balance.overdrawn && "wrong"}>
              {@balance.left} <small>if approved</small>
            </dd>
          </dl>
          <p :if={@balance.overdrawn}>
            That is more leave than the balance holds. It can still be approved.
          </p>
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

  # A request that is not there and one that has been decided since the link was followed answer
  # the same: there is nothing here to change.
  defp opened(socket, :amend, %{"id" => id}, today) do
    with {:ok, request} <- Leave.fetch_request(id),
         true <- Leave.revisable?(request, socket.assigns.current_person) do
      amending(socket, request, today)
    else
      _refused ->
        socket
        |> put_flash(:error, "That request is not yours to change.")
        |> push_navigate(to: ~p"/leave")
    end
  end

  defp amending(socket, request, today) do
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

    socket
    |> assign(:person, person)
    |> assign(:ready?, ready?)
    |> assign(:held, held(person, today, ready?))
  end

  defp held(_person, _today, false), do: %{}

  defp held(person, today, true) do
    person |> Ledger.statements(today) |> Map.new(&{&1.leave_type.id, &1})
  end

  # Which types can be asked for turns on the dates being asked about, so a stretch that is over
  # offers what was offered then: leave is filed after the entitlement that covered it has closed as
  # readily as before. A form nobody has put dates in yet asks about today.
  defp choices(socket, order) do
    today = socket.assigns.today
    offered = Leave.requestable(socket.assigns.person, order.span || Date.range(today, today))

    assign(
      socket,
      :leave_types,
      Enum.map(offered, &{offering(&1, socket.assigns.held[&1.id]), &1.id})
    )
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

    case {params[moved], params[other]} do
      {entered, _kept} when entered in [nil, ""] -> params
      {entered, kept} when kept in [nil, ""] -> Map.put(params, other, entered)
      {entered, kept} -> Map.put(params, other, ordered(moved, entered, kept))
    end
  end

  defp other("from"), do: "to"
  defp other("to"), do: "from"

  defp ordered("from", entered, kept), do: max(entered, kept)
  defp ordered("to", entered, kept), do: min(entered, kept)

  defp filled(socket, params) do
    changeset = Leave.change_order(socket.assigns.person, params)
    order = Ecto.Changeset.apply_changes(changeset)
    days = Leave.days_for(socket.assigns.person, changeset)
    problems = problems(socket, changeset, order, days)
    entries = filable(days, problems)

    socket
    |> choices(order)
    |> assign(:form, to_form(changeset, as: :request))
    |> assign(:order, order)
    |> assign(:entries, entries)
    |> assign(:problems, problems)
    |> assign(:portion, portion(socket, order))
    |> assign(:filing, filing(socket, order, entries))
    |> assign(:balance, moving(projection(socket, entries)))
    |> assign(:replacing, replacing(socket.assigns.replaced, entries))
  end

  # Nothing is filed while anything is wrong with what was asked for: what a refusal leaves is a
  # form to fix rather than days to send, and a balance nobody has to be shown.
  defp filable(_days, [_problem | _rest]), do: []
  defp filable(days, []), do: days

  # Part of a day can only be asked of one day, so the field is there for one date and gone for a
  # stretch. It turns on the dates alone and not on what has been typed into it, so that a half
  # finished number cannot take the field out from under whoever is typing it.
  defp portion(socket, %{span: %Date.Range{first: date, last: date}}) do
    whole_day(socket.assigns.person, date)
  end

  defp portion(_socket, _order), do: nil

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
  # comes to, so asking for a week that holds one working day still shows the week. One date has no
  # rows worth reading — it is the field above and the hours beside it.
  defp filing(_socket, _order, []), do: nil
  defp filing(_socket, %{span: %Date.Range{first: date, last: date}}, _entries), do: nil

  defp filing(socket, order, entries) do
    worked = Map.new(Leave.working_days(socket.assigns.person, order.span))

    %{days: Enum.map(order.span, &day(&1, worked[&1])), total: total(entries)}
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

  # Whatever about the instruction stops it being answerable, one thing at a time. What the order
  # itself refuses it says in its own words; a refusal that names a date is said here, because
  # reading a date out is the page's business.
  defp problems(socket, changeset, order, days) do
    case Enum.map(changeset.errors, fn {_field, error} -> translate_error(error) end) do
      [] -> refusals(socket, order, days)
      said -> said
    end
  end

  # Nothing chosen is not a problem to report, it is a form nobody has filled in yet.
  defp refusals(_socket, %{leave_type_id: nil}, _days), do: []
  defp refusals(_socket, order, []), do: unworked(order)
  defp refusals(socket, _order, days), do: clashing(socket, days)

  # One date names itself, the way the hours in a day do. A stretch cannot without listing a
  # weekend back at somebody who can see it is a weekend.
  defp unworked(%{span: nil}), do: []

  defp unworked(%{span: %Date.Range{first: date, last: date}}) do
    ["You do not work on #{Wording.weekday(date)}."]
  end

  defp unworked(_order), do: ["You do not work on any of those days."]

  # A day off is at most what is left of the day: the hours worked on it, less the leave already
  # filed into it. Every date that will not fit is named, because fixing the first would otherwise
  # only turn up the next.
  defp clashing(socket, days) do
    socket.assigns.person
    |> Leave.clashes(Leave.proposed(days), socket.assigns.request)
    |> Enum.map(&spoken_for/1)
  end

  defp spoken_for({date, free}) do
    case Decimal.positive?(free) do
      true -> "#{Wording.weekday(date)} has only #{Wording.figure(free, :hours)} free."
      false -> "You already have leave on #{Wording.weekday(date)}."
    end
  end

  defp projection(_socket, []), do: nil

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

  # One leave type is asked for, so one balance is left, and it is said whether the request is a
  # stretch of days or a single one. What the leave draws is the table's own total, which is why
  # the figure it came off is not shown beside it.
  defp moving(nil), do: nil
  defp moving(statement), do: Wording.projected(statement)

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

  # Every refusal the write path can give about the days, this page has already said in its own
  # words, so one coming back means they changed underneath it between the reading and the write:
  # reading them again is what says so. A refusal the reading does not turn up — days nobody filled
  # in, or anything the write path learns to refuse later — still leaves something said, because a
  # page that comes back unchanged and silent reads as a button that does nothing.
  defp saved(socket, {:error, _changeset}) do
    socket |> filled(socket.assigns.form.params) |> unexplained()
  end

  defp unexplained(%{assigns: %{problems: []}} = socket) do
    assign(socket, :problems, ["That could not be filed. Check what it asks for and try again."])
  end

  defp unexplained(socket), do: socket
end
