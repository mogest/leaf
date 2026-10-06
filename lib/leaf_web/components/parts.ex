defmodule LeafWeb.Parts do
  @moduledoc """
  The parts more than one page is assembled from.

  A part here is one the stylesheet had to be told the name of, and everything inside it is
  selected by element. Anything only one page shows belongs to that page instead.
  """

  use Phoenix.Component
  use LeafWeb, :verified_routes

  import Phoenix.LiveView, only: [put_flash: 3]

  alias Leaf.Leave
  alias Leaf.Wording

  @weekdays [
    {"M", "Monday"},
    {"T", "Tuesday"},
    {"W", "Wednesday"},
    {"T", "Thursday"},
    {"F", "Friday"},
    {"S", "Saturday"},
    {"S", "Sunday"}
  ]

  @settings [
    {"Organisation", "/settings", "organisation"},
    {"Leave types", "/settings/leave-types", "leave-types"},
    {"Policies", "/settings/policies", "policies"},
    {"Calendars", "/settings/calendars", "calendars"},
    {"Audit log", "/settings/audit", "audit"}
  ]

  @doc """
  The way between the things an administrator configures.

  ## Examples

      <Parts.settings_nav here="leave-types" />

  """
  attr :here, :string, required: true, doc: "which of them is being looked at"

  def settings_nav(assigns) do
    ~H"""
    <nav class="tabs">
      <ul>
        <li :for={{label, path, name} <- settings()}>
          <.link navigate={path} aria-current={name == @here && "page"}>{label}</.link>
        </li>
      </ul>
    </nav>
    """
  end

  defp settings, do: @settings

  @doc """
  What somebody holds, a leave type at a time, as at today.

  Each one is a `t:Leaf.Wording.held/0` with the ledger it opens onto, worked out before it
  arrives here.

  ## Examples

      <Parts.balance_sheet balances={@balances} title="Balances" path={~p"/balances"} />

  """
  attr :balances, :list, required: true, doc: "the balances to show, already put into words"
  attr :title, :string, required: true, doc: "what to call them"
  attr :path, :string, default: nil, doc: "where the heading leads, where it leads anywhere"

  slot :empty, doc: "what to say where there are none; without it, none means no card at all"

  def balance_sheet(assigns) do
    ~H"""
    <section :if={@balances != [] or @empty != []} class="balance-sheet">
      <header>
        <.heading title={@title} path={@path}><small>as at today</small></.heading>
      </header>
      <dl :if={@balances != []}>
        <%= for balance <- @balances do %>
          <dt><.link navigate={balance.path}>{balance.name}</.link></dt>
          <dd>{balance.amount} <small>{balance.unit}</small></dd>
          <dd :if={balance.awaiting} data-awaiting>{balance.awaiting}</dd>
          <dd :if={balance.expiry}>{balance.expiry}</dd>
        <% end %>
      </dl>
      <p :if={@balances == []}>{render_slot(@empty)}</p>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :path, :string, default: nil
  slot :inner_block, required: true

  defp heading(%{path: nil} = assigns) do
    ~H"""
    <h2>{@title} {render_slot(@inner_block)}</h2>
    """
  end

  defp heading(assigns) do
    ~H"""
    <h2><.link navigate={@path}>{@title}</.link> {render_slot(@inner_block)}</h2>
    """
  end

  @doc """
  What can be done to the row it ends: a `⋯` that opens a menu of it.

  The menu is a popover, placed under its button when it opens. An item that cannot be undone
  carries `data-confirm`, which is also what marks it as one.

  ## Examples

      <Parts.row_menu id={"holiday-\#{holiday.id}"} label={holiday.name}>
        <button type="button" phx-click="remove" data-confirm="Remove this holiday?">Remove</button>
      </Parts.row_menu>

  """
  attr :id, :string, required: true, doc: "the menu's id, unique on the page"
  attr :label, :string, required: true, doc: "what the row is, for the button's accessible name"

  slot :inner_block, required: true, doc: "the links and buttons the menu offers"

  def row_menu(assigns) do
    ~H"""
    <button type="button" popovertarget={@id} aria-label={"Actions for #{@label}"}>⋯</button>
    <div id={@id} popover phx-hook=".RowMenu">
      {render_slot(@inner_block)}
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".RowMenu">
      export default {
        mounted() {
          this.el.addEventListener("beforetoggle", ({newState}) => {
            if (newState !== "open") return
            const {bottom, right} = this.el.previousElementSibling.getBoundingClientRect()
            this.el.style.top = `${bottom + window.scrollY}px`
            this.el.style.right = `${document.documentElement.clientWidth - right}px`
          })
          this.el.addEventListener("click", () => this.el.hidePopover())
        }
      }
    </script>
    """
  end

  @doc """
  Requests as a record of them: a row each, a column for every part of one.

  Each one is a `t:Leaf.Wording.filed/0`, worked out before it arrives here. One carrying a
  `path` is opened by its row. With `cancel`, one carrying `cancellable?` offers cancelling it in
  its menu, which sends `"cancel-request"` for the page to answer with `cancel_request/2`.

  ## Examples

      <Parts.requests requests={@requests}>
        <:empty>You have not asked for any leave yet.</:empty>
      </Parts.requests>

  """
  attr :requests, :list, required: true, doc: "the requests to show, already put into words"

  attr :title, :string,
    default: nil,
    doc: "what to call them, where the page has not said already"

  attr :cancel, :boolean, default: false, doc: "whether the page answers `\"cancel-request\"`"

  slot :empty, required: true, doc: "what to say where there are none"
  slot :footer, doc: "anything to say under the list"

  def requests(assigns) do
    ~H"""
    <section class="requests">
      <header :if={@title}>
        <h2>{@title}</h2>
      </header>
      <div :if={@requests != []}>
        <table>
          <thead>
            <tr>
              <th scope="col">When</th>
              <th scope="col">Leave</th>
              <th scope="col">Amount</th>
              <th scope="col">Standing</th>
              <th scope="col">Who and when</th>
              <th :if={@cancel} scope="col"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={request <- @requests} data-tone={tone(request.standing)}>
              <th scope="row">
                <.link :if={request[:path]} navigate={request[:path]}>{request.dates}</.link>
                <span :if={!request[:path]}>{request.dates}</span>
              </th>
              <td>{request.type}</td>
              <td>{request.amount}</td>
              <td>
                <span class="standing" data-standing={request.standing}>{request.label}</span>
              </td>
              <td>{request.progress}</td>
              <td :if={@cancel}>
                <.row_menu
                  :if={request.cancellable?}
                  id={"request-#{request.id}"}
                  label={request.dates}
                >
                  <button
                    type="button"
                    phx-click="cancel-request"
                    phx-value-id={request.id}
                    data-confirm="Cancel this leave? The request is cancelled and what it drew returned."
                  >
                    Cancel
                  </button>
                </.row_menu>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p :if={@requests == []}>{render_slot(@empty)}</p>
      <p :if={@footer != []}>{render_slot(@footer)}</p>
    </section>
    """
  end

  @doc """
  Cancels the request `id` names as whoever is signed in, and says how that went.

  Whether they may is `Leaf.Leave`'s to decide; the page reloads what it shows afterwards.
  """
  @spec cancel_request(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def cancel_request(socket, id) do
    written =
      with {:ok, request} <- Leave.fetch_request(id),
           do: Leave.cancel(request, socket.assigns.current_person)

    cancelled(socket, written)
  end

  @doc """
  Puts on `row` what `viewer` may do to `request`: amend it by its `path`, and cancel it.

  `Leaf.Leave.revisable?/2` answers both, so a row offers the two together or neither.
  """
  @spec revisable(map(), Leave.Request.t(), Leaf.People.Person.t()) :: map()
  def revisable(row, request, viewer) do
    case Leave.revisable?(request, viewer) do
      true -> Map.merge(row, %{path: ~p"/leave/#{request}/amend", cancellable?: true})
      false -> Map.merge(row, %{path: nil, cancellable?: false})
    end
  end

  defp cancelled(socket, {:ok, _request}),
    do: put_flash(socket, :info, "The request is cancelled.")

  defp cancelled(socket, refused) when refused in [:error, {:error, :forbidden}] do
    put_flash(socket, :error, "That is not yours to cancel.")
  end

  defp cancelled(socket, {:error, _changeset}) do
    put_flash(socket, :error, "The request would not cancel.")
  end

  # Leave that was given back or refused is over, and the row it is on reads as the past.
  defp tone(standing) when standing in [:cancelled, :declined], do: "past"
  defp tone(_standing), do: nil

  @doc """
  Months side by side, each day marked with what is on it, and a step either way.

  ## Examples

      <Parts.calendar months={@months} today={@today} earlier={@earlier} later={@later} />

  """
  attr :months, :list, required: true, doc: "the `Leaf.Leave.Month` structs to show"
  attr :today, Date, required: true, doc: "the date to mark as today"
  attr :earlier, :string, required: true, doc: "where the step backwards goes"
  attr :later, :string, required: true, doc: "where the step forwards goes"

  def calendar(assigns) do
    ~H"""
    <section class="calendar">
      <header>
        <h2>Calendar</h2>
        <.steps earlier={@earlier} later={@later} what="months" />
      </header>
      <div>
        <table :for={month <- @months}>
          <caption>{Wording.month(month.starts_on, @today)}</caption>
          <thead>
            <tr>
              <th :for={{initial, weekday} <- weekdays()} scope="col">
                <abbr title={weekday}>{initial}</abbr>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={week <- month.weeks}>
              <td
                :for={day <- week}
                data-working={working(day)}
                data-leave={leave(day)}
                data-part={part?(day)}
                data-holiday={holiday(day)}
                data-today={today?(day, @today)}
                aria-current={today?(day, @today) && "date"}
              >
                {number(day)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <ul class="legend">
        <li data-leave="approved">Approved</li>
        <li data-leave="pending">Waiting</li>
        <li data-leave="approved" data-part>Part of the day</li>
        <li data-holiday>Public holiday</li>
        <li data-today>Today</li>
      </ul>
    </section>
    """
  end

  @doc """
  A step back and a step on, either side of the stretch of time being shown.

  ## Examples

      <Parts.steps earlier={@earlier} later={@later} what="months" />

  """
  attr :earlier, :string, required: true, doc: "where the step backwards goes"
  attr :later, :string, required: true, doc: "where the step forwards goes"
  attr :what, :string, required: true, doc: "what a step moves by, for the label"

  def steps(assigns) do
    ~H"""
    <.link class="step" navigate={@earlier} aria-label={"Earlier #{@what}"} title={"Earlier #{@what}"}>
      <.arrow d="M10 3L5 8l5 5" />
    </.link>
    <.link class="step" navigate={@later} aria-label={"Later #{@what}"} title={"Later #{@what}"}>
      <.arrow d="M6 3l5 5-5 5" />
    </.link>
    """
  end

  attr :d, :string, required: true

  defp arrow(assigns) do
    ~H"""
    <svg
      width="12"
      height="12"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      stroke-width="1.7"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d={@d} />
    </svg>
    """
  end

  defp weekdays, do: @weekdays

  defp working(%{working?: false}), do: "no"
  defp working(_day), do: nil

  defp leave(%{leave: leave}), do: leave
  defp leave(nil), do: nil

  defp part?(%{part?: part?}), do: part?
  defp part?(nil), do: false

  defp holiday(%{holiday: holiday}), do: holiday
  defp holiday(nil), do: nil

  defp today?(%{date: date}, today), do: date == today
  defp today?(nil, _today), do: false

  defp number(%{date: date}), do: date.day
  defp number(nil), do: nil
end
