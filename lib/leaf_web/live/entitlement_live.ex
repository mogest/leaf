defmodule LeafWeb.EntitlementLive do
  @moduledoc """
  What one policy grants for one leave type, over one stretch of time.

  Every rule §4.5 lists is a field here, offered only where the choices before it leave it meaning
  anything: an amount that grants nothing wants no grant period, and an entitlement that never
  lapses wants no cap. The changeset clears whatever the form stops offering.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Changeset
  alias Leaf.Ledger
  alias Leaf.Org
  alias Leaf.Policies
  alias LeafWeb.Chart

  @bases [
    {"Employee start date", "employment_date"},
    {"Employee birthdate", "birthday"},
    {"Calendar year", "calendar_year"},
    {"Financial year", "organisation_year"}
  ]

  @periods [{"Month", "month"}, {"Quarter", "quarter"}, {"Year", "year"}]

  @figures ["Granted in the first year", "Highest balance", "Lost over three years"]

  @lost_to %{expiry: "to expiry", rollover_cap: "above the cap"}

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Policies.fetch_leave_policy(params["policy_id"]) do
      {:ok, policy} ->
        {:ok, opened(socket, policy, amending(socket.assigns.live_action, policy, params))}

      :error ->
        {:ok, unknown(socket)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"policy_entitlement" => params}, socket) do
    changeset = change(socket.assigns, Map.merge(socket.assigns.defaults, params))

    socket =
      socket
      |> formed(changeset, action: :validate)
      |> assign(:unfunded, [])
      |> rehearsing(changeset)

    {:noreply, socket}
  end

  @role :admin
  def handle_event("show", %{"index" => index}, socket) do
    {:noreply, assign(socket, :shown, String.to_integer(index))}
  end

  @role :admin
  def handle_event("save", %{"policy_entitlement" => params} = submitted, socket) do
    params = Map.merge(socket.assigns.defaults, params)
    written = write(socket.assigns, params, submitted["confirmed"] == "true")

    {:noreply, socket |> assign(:unfunded, []) |> saved(written)}
  end

  @impl Phoenix.LiveView
  def handle_async(:rehearsal, {:ok, {:ok, rehearsals}}, socket) do
    {:noreply, assign(socket, rehearsals: rehearsals, rehearsing: false, refused: false)}
  end

  # Refused or crashed, the last result stays, marked as no longer describing the form.
  def handle_async(:rehearsal, _refused, socket) do
    {:noreply, assign(socket, rehearsing: false, refused: true)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="entitlement" rail="settings" viewer={@viewer}>
      <header>
        <nav aria-label="Breadcrumb">
          <.link navigate={~p"/settings/policies"}>Leave policies</.link>
          <.link navigate={~p"/settings/policies/#{@policy}"}>{@policy.name}</.link>
        </nav>
        <h1>{@title}</h1>
      </header>

      <.form id="entitlement" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>When it applies</h2>
          </header>
          <.input
            :if={!@entitlement}
            field={@form[:leave_type_id]}
            type="select"
            label="Leave type"
            prompt="Choose one"
            options={@leave_types}
          />
          <.input
            field={@form[:effective_from]}
            type="date"
            phx-debounce="500"
            label="Offered from"
            help="The day these terms start. To change them later, set Stops granting after on this entitlement
              and add a new one from the next day."
          />
          <div>
            <.input
              field={@form[:granted_to]}
              type="date"
              phx-debounce="500"
              label="Stops granting after"
              help="Leave empty unless these terms are ending. Nothing more is granted after this day, but
                balances already granted can still be taken."
            />
            <.input
              field={@form[:effective_to]}
              type="date"
              phx-debounce="500"
              label="Stops being spendable after"
              help="Leave empty unless this leave is being withdrawn. Leave dated after this day can't be taken,
                and unused balances are lost. Set it later than Stops granting after to give people time to use
                what they have."
            />
          </div>
        </section>

        <section>
          <header>
            <h2>What it grants</h2>
          </header>
          <.radios
            field={@form[:amount_source]}
            label="Where the amount comes from"
            help="A fixed amount: a set number of hours or days each period. Their share of the public holiday
              calendar: holidays become ordinary working days, and each person gets leave to cover the ones on
              their calendar, so a part-timer who never works Mondays still gets their share. No balance: for
              leave like unpaid leave, which is taken but not earned."
          >
            <:option value="fixed" label="A fixed amount of">
              <.input
                field={@form[:grant_amount]}
                phx-debounce="500"
                aria-label="A fixed amount of"
                unit={amount_unit(@types[@terms.leave_type_id], @terms.pro_rated_by_fte)}
              />
            </:option>
            <:option value="public_holidays" label="Their share of the public holiday calendar" />
            <:option value="none" label="No balance; time off is just recorded" />
          </.radios>
          <%= if @terms.amount_source != :none do %>
            <.input
              field={@form[:pro_rated_by_fte]}
              type="checkbox"
              label="Pro-rated by the hours they work"
              help="Tick to scale the amount to each person's hours: someone working three days a week gets 60%
                of it, and a fixed amount is entered as what someone working full time gets. Leave unticked to
                give everyone the same amount."
            />
            <div>
              <.input
                field={@form[:grant_period]}
                type="select"
                label="Grant period"
                options={periods(@terms.grant_basis)}
                help="The stretch of time the amount is for. It builds up across each period or lands at its
                  start. A rollover cap, or expiring at the end of the period, applies as each period ends."
              />
              <.input
                field={@form[:grant_basis]}
                type="select"
                label="Aligned to"
                options={@bases}
                help="When each period starts. Employee start date: periods run from the day they joined, so
                  years start on each work anniversary. Employee birthdate: years start on their birthday, and
                  anyone with no birthdate recorded gets nothing. Calendar year: years start on 1 January,
                  quarters every three months from it, months on the 1st. Financial year: the same, counted from
                  the first month of your financial year."
              />
            </div>
            <.radios
              field={@form[:grant_timing]}
              label="How it arrives"
              value={@terms.grant_timing}
              help="Accrues day by day: the balance builds through the period from their first day. Evenly over
                the period: 160 hours a year is 0.44 hours every day, so March earns 13.59 and February 12.27.
                Evenly over each month, for a fixed yearly amount: every month earns 13.33 hours, spread across
                its days, so a day in February is worth more than a day in March. Lands whole: the full amount
                arrives on the period's first day. Anyone who joins or moves onto these terms part-way through a
                period gets nothing until the next one, including everyone if this entitlement starts
                mid-period. A public holiday allowance lands whole only when aligned to the start date."
            >
              <:option value="daily" label="Accrues day by day, evenly over the period" />
              <:option
                :if={@terms.amount_source == :fixed and @terms.grant_period == :year}
                value="monthly"
                label="Accrues day by day, evenly over each month"
              />
              <:option
                :if={
                  @terms.amount_source != :public_holidays or @terms.grant_basis == :employment_date
                }
                value="period_start"
                label="Lands whole when the period opens"
              />
            </.radios>
            <.input
              :if={@terms.amount_source == :fixed and @terms.grant_timing in [:daily, :monthly]}
              field={@form[:suspension_allowance_weeks]}
              type="text"
              phx-debounce="500"
              label="Unpaid leave allowance"
              unit="weeks"
              help="Leave that pauses accrual, such as unpaid leave, normally earns nothing. In each period, up to
                this many weeks of it still earn leave, counted afresh every period. Once leave has been taken,
                this can be raised but not lowered or removed."
            />
          <% end %>
        </section>

        <section>
          <header>
            <h2>How long a new starter waits</h2>
          </header>
          <div>
            <.input
              :if={@terms.amount_source == :fixed}
              field={@form[:qualifying_months]}
              type="number"
              phx-debounce="500"
              label="First granted after"
              unit="months' service"
              help="Leave empty to grant from their first day. With 6, nothing is granted until six months after
                they join. Aligned to the start date, each period then runs from that date, and current staff's
                periods move too, so replacing an entitlement that lands whole skips the grant for the period
                the replacement starts in. Aligned to anything else, the periods stay put and the wait ending
                part-way through one is treated like joining part-way through it."
            />
            <.input
              field={@form[:takeable_after_months]}
              type="number"
              phx-debounce="500"
              label="Can be taken after"
              unit="months' service"
              help="Leave empty to let them book it from their first day, going into a negative balance if
                nothing has been granted yet. Leave already booked inside the wait can be approved or cancelled,
                but not changed."
            />
          </div>
        </section>

        <section :if={@terms.amount_source != :none}>
          <header>
            <h2>What happens to unused leave</h2>
          </header>
          <.radios
            field={@form[:expiry_rule]}
            label="At the end of each period"
            help="What happens to an unused balance: carried over in full, carried over up to a cap, or lost.
              Expiring a fixed window after it's granted suits leave tied to a date, such as a birthday: 14 days
              means birthday leave must be taken within two weeks of the birthday."
          >
            <:option value="never" label="Rolls over indefinitely" />
            <:option value="cap" label="Rolls over up to a cap of">
              <.input
                field={@form[:rollover_cap]}
                phx-debounce="500"
                aria-label="Rolls over up to a cap of"
                unit={unit(@types[@terms.leave_type_id])}
              />
            </:option>
            <:option value="grant_period_end" label="Expires at the end of its period" />
            <:option value="window" label="Expires within">
              <.input
                field={@form[:expiry_window_days]}
                type="number"
                phx-debounce="500"
                aria-label="Expires within"
                unit="days of being granted"
              />
            </:option>
          </.radios>
        </section>

        <section :if={@terms.amount_source != :none}>
          <header>
            <h2>Leave the balance doesn't cover</h2>
          </header>
          <.radios
            field={@form[:balance_check]}
            label="Needs an administrator to approve it"
            help="Today's balance is what the person has now, after all their approved leave is taken off,
              including leave booked for later. The second option also counts the leave they'll build up before
              the last day they've asked for. Either way, they can still make the request, but only an
              administrator can approve it, not their manager, and leave that's usually approved automatically
              will wait for one."
          >
            <:option value="off" label="Never" />
            <:option value="today" label="If today's balance doesn't cover it" />
            <:option value="projected" label="If the balance won't cover it by the time it's taken" />
          </.radios>
        </section>

        <section :if={@unfunded != []}>
          <header>
            <h2>Booked leave this change would leave unfunded</h2>
          </header>
          <p>
            What these days draw on expires before them. Saving anyway leaves each person's balance
            negative by what they take.
          </p>
          <ul>
            <li :for={{person, dates} <- @unfunded}>
              {person.name}: {Enum.map_join(dates, ", ", &Wording.date/1)}
            </li>
          </ul>
        </section>

        <footer>
          <button :if={@unfunded == []} class="button" type="submit">Save</button>
          <button :if={@unfunded != []} class="button" type="submit" name="confirmed" value="true">
            Save anyway
          </button>
          <.link navigate={~p"/settings/policies/#{@policy}"}>Cancel</.link>
        </footer>
      </.form>

      <aside :if={@rehearsing or @refused or @rehearsals != []} aria-busy={to_string(@rehearsing)}>
        <header>
          <h2>Preview</h2>
          <p :if={@refused} role="status">Fix the errors to see the preview.</p>
          <p :if={@drawn_on}>
            Leave has been taken under this entitlement, so changes to its terms can't be saved.
            To change them, set "Stops granting after" and add a new entitlement.
          </p>
        </header>
        <p>
          <button
            :for={{name, index} <- Enum.with_index(@samples)}
            type="button"
            phx-click="show"
            phx-value-index={index}
            aria-pressed={to_string(index == @shown)}
          >
            {name}
          </button>
        </p>
        <.played_out
          name={Enum.at(@samples, @shown)}
          rehearsal={Enum.at(@rehearsals, @shown, @placeholder)}
        />
      </aside>
    </Layouts.app>
    """
  end

  attr :name, :string, required: true
  attr :rehearsal, :map, required: true

  defp played_out(assigns) do
    ~H"""
    <figure>
      <svg viewBox="0 0 600 200" role="group" aria-label={"Balance over three years, #{@name}"}>
        <line x1="0" y1={@rehearsal.line.zero} x2="600" y2={@rehearsal.line.zero} />
        <line :for={x <- [200, 400]} x1={x} y1="0" x2={x} y2="200" />
        <polyline points={@rehearsal.line.points} />
        <g :for={loss <- @rehearsal.line.losses}>
          <circle cx={loss.x} cy={loss.y} r="7" tabindex="0" role="img" aria-label={loss.label} />
          <foreignObject x={loss.label_x} y={loss.y + 14} width="360" height="200" aria-hidden="true">
            <p>{loss.label}</p>
          </foreignObject>
        </g>
      </svg>
      <figcaption>
        <span>{@rehearsal.from}</span><span>{@rehearsal.to}</span>
      </figcaption>
      <ul>
        <li>
          <svg width="16" height="16" aria-hidden="true"><polyline points="0,8 16,8" /></svg>Balance
        </li>
        <li>
          <svg width="16" height="16" aria-hidden="true"><circle cx="8" cy="8" r="5" /></svg>Leave lost
        </li>
      </ul>
      <dl>
        <div :for={{label, figure} <- @rehearsal.figures}>
          <dt>{label}</dt>
          <dd>{figure}</dd>
        </div>
      </dl>
    </figure>
    """
  end

  defp amending(:new, _policy, _params), do: {:ok, nil}
  defp amending(:edit, policy, %{"id" => id}), do: Policies.fetch_entitlement(policy, id)

  defp opened(socket, policy, {:ok, entitlement}) do
    {:ok, organisation} = Org.fetch_organisation(policy.organisation_id)
    offered = Policies.leave_types_offered(policy.organisation_id)

    # The picker offers only what is still offered, but the amount's unit is that of the type this
    # entitlement is already on, which may be one that has since been withdrawn.
    types = Policies.leave_types(policy.organisation_id)

    socket =
      socket
      |> assign(:page_title, title(entitlement))
      |> assign(:title, title(entitlement))
      |> assign(:policy, policy)
      |> assign(:entitlement, entitlement)
      |> assign(:leave_types, Enum.map(offered, &{Wording.leave_type(&1), &1.id}))
      |> assign(:types, Map.new(types, &{&1.id, &1}))
      |> assign(:bases, @bases)
      |> assign(:unfunded, [])
      |> assign(:samples, Ledger.rehearsal_names(policy.organisation_id))
      |> assign(:rehearsals, [])
      |> assign(:rehearsing, false)
      |> assign(:refused, false)
      |> assign(:shown, 0)
      |> assign(:drawn_on, entitlement != nil and Policies.drawn_on?(entitlement))
      |> assign(:defaults, opening(entitlement, organisation))

    changeset = change(socket.assigns, socket.assigns.defaults)

    {from, to} =
      Ledger.rehearsal_dates(organisation, Ecto.Changeset.get_field(changeset, :effective_from))

    socket
    |> formed(changeset)
    |> assign(:placeholder, placeholder(from, to))
    |> rehearsing(changeset)
  end

  defp opened(socket, policy, :error) do
    socket
    |> put_flash(:error, "Entitlement not found.")
    |> push_navigate(to: ~p"/settings/policies/#{policy}")
  end

  defp unknown(socket) do
    socket
    |> put_flash(:error, "Policy not found.")
    |> push_navigate(to: ~p"/settings/policies")
  end

  defp title(nil), do: "Add an entitlement"
  defp title(entitlement), do: entitlement.leave_type.name

  # A leave type is settled when the entitlement is created: moving one to another type would
  # silently re-file everything already granted under it.
  defp change(%{entitlement: nil} = assigns, params) do
    Policies.change_entitlement(assigns.policy, chosen(assigns, params), params)
  end

  defp change(assigns, params), do: Changeset.change(assigns.entitlement, params)

  defp chosen(assigns, params), do: assigns.types[params["leave_type_id"]]

  # An entitlement that has always applied starts where the organisation's records do: nothing
  # before that date grants anything anyway. A new one's fields fall back to these when the form
  # stops offering them, so choosing one option and returning to another restores their defaults.
  defp opening(nil, organisation) do
    %{
      "effective_from" => to_string(organisation.tracked_from),
      "amount_source" => "fixed",
      "grant_period" => "year",
      "grant_basis" => "employment_date",
      "grant_timing" => "daily",
      "pro_rated_by_fte" => "true",
      "expiry_rule" => "never"
    }
  end

  defp opening(_entitlement, _organisation), do: %{}

  # The terms are read once the changeset has settled them, so that what is offered follows what
  # it will save rather than what was submitted.
  defp formed(socket, changeset, opts \\ []) do
    assign(socket, form: to_form(changeset, opts), terms: Ecto.Changeset.apply_changes(changeset))
  end

  defp periods(:birthday), do: [{"Year", "year"}]
  defp periods(_basis), do: @periods

  # The amount is a full-time figure only where it is pro-rated, so the unit says so.
  defp amount_unit(type, true), do: String.trim("#{unit(type)} at 1.0 FTE")
  defp amount_unit(type, _pro_rated), do: unit(type)

  defp unit(nil), do: nil
  defp unit(type), do: to_string(type.unit)

  # A new run supersedes the one in flight, whose result is then ignored; it is left to roll back
  # rather than killed mid-transaction. With no leave type there is nothing to run, but one is still
  # started so that the superseded result is ignored.
  defp rehearsing(socket, changeset) do
    leave_type = socket.assigns.types[Ecto.Changeset.get_field(changeset, :leave_type_id)]

    socket
    |> assign(:rehearsing, leave_type != nil)
    |> start_async(:rehearsal, fn -> rehearsed(changeset, leave_type) end)
  end

  defp rehearsed(_changeset, nil), do: {:ok, []}

  defp rehearsed(changeset, leave_type) do
    with {:ok, rehearsals} <- Ledger.rehearse(changeset) do
      {:ok, Enum.map(rehearsals, &described(&1, leave_type.unit))}
    end
  end

  defp described(rehearsal, unit) do
    {from, _opening} = List.first(rehearsal.balances)
    {to, _closing} = List.last(rehearsal.balances)
    losses = Enum.map(rehearsal.losses, &{&1.date, lost(&1, unit)})

    %{
      from: Wording.brief_date(from),
      to: Wording.brief_date(to),
      line: line(rehearsal.balances, losses, from, to),
      figures:
        Enum.zip(
          @figures,
          Enum.map([rehearsal.granted, rehearsal.held, rehearsal.lost], &Wording.figure(&1, unit))
        )
    }
  end

  defp placeholder(from, to) do
    %{
      from: Wording.brief_date(from),
      to: Wording.brief_date(to),
      line: %{zero: 195, points: "", losses: []},
      figures: for(label <- @figures, do: {label, ""})
    }
  end

  defp line(balances, losses, from, to) do
    place = Chart.placing(from, to, Enum.map(balances, &elem(&1, 1)))
    {_x, zero} = place.({from, Decimal.new(0)})

    %{
      zero: zero,
      points: Chart.points(balances, place),
      losses:
        for(
          {date, label} <- losses,
          {x, y} = place.(List.keyfind!(balances, date, 0)),
          do: %{x: x, y: y, label: label, label_x: Chart.label_x(x)}
        )
    }
  end

  defp lost(movement, unit) do
    "Loses #{Wording.figure(Decimal.abs(movement.amount), unit)} #{@lost_to[movement.kind]} on " <>
      Wording.date(movement.date)
  end

  defp write(%{entitlement: nil} = assigns, params, _confirmed) do
    created(assigns, params, chosen(assigns, params))
  end

  defp write(assigns, params, true) do
    Policies.update_entitlement(assigns.entitlement, assigns.current_person, params)
  end

  defp write(assigns, params, false) do
    case Ledger.unfunded_by(assigns.entitlement, params) do
      [] -> write(assigns, params, true)
      unfunded -> {:unfunded, unfunded}
    end
  end

  # An unchosen leave type is a blank the changeset already knows how to refuse.
  defp created(assigns, params, nil), do: {:error, change(assigns, params)}

  defp created(assigns, params, leave_type) do
    Policies.create_entitlement(assigns.policy, leave_type, assigns.current_person, params)
  end

  defp saved(socket, {:ok, _entitlement}) do
    socket
    |> put_flash(:info, "Saved.")
    |> push_navigate(to: ~p"/settings/policies/#{socket.assigns.policy}")
  end

  defp saved(socket, {:unfunded, unfunded}), do: assign(socket, :unfunded, unfunded)

  defp saved(socket, {:error, :drawn_on}) do
    put_flash(
      socket,
      :error,
      "Leave has already been taken under this entitlement. Only its end dates can be changed, and " <>
        "its unpaid leave allowance can only go up. To change anything else, set \"Stops granting " <>
        "after\" and add a new entitlement."
    )
  end

  defp saved(socket, {:error, changeset}), do: formed(socket, changeset, action: :validate)
end
