defmodule LeafWeb.EntitlementLive do
  @moduledoc """
  What one policy grants for one leave type, over one stretch of time.

  Every rule §4.5 lists is a field here, and which of them apply to each other is the changeset's
  to say rather than the form's: an amount that grants nothing wants no grant period, and an
  entitlement that never lapses wants no cap. The form offers them all and reports the refusal.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Changeset
  alias Leaf.Ledger
  alias Leaf.Org
  alias Leaf.Policies
  alias Phoenix.HTML.Form

  @sources [
    {"A fixed amount", "fixed"},
    {"Their share of the public holiday calendar", "public_holidays"},
    {"Nothing — recorded only", "none"}
  ]

  @bases [
    {"Their employment start date", "employment_date"},
    {"Their birthday", "birthday"},
    {"The calendar year", "calendar_year"},
    {"The organisation's financial year", "organisation_year"}
  ]

  @periods [{"a month", "month"}, {"a quarter", "quarter"}, {"a year", "year"}]

  @timings [
    {"Accrues day by day", "daily"},
    {"Lands whole when the period opens", "period_start"}
  ]

  @rules [
    {"Rolls over indefinitely", "never"},
    {"Rolls over up to a cap", "cap"},
    {"Lapses at the end of its period", "grant_period_end"},
    {"Lapses a fixed window after it lands", "window"}
  ]

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
    changeset = change(socket.assigns, params)

    socket =
      socket
      |> assign(:form, to_form(changeset, action: :validate))
      |> assign(:unfunded, [])

    {:noreply, socket}
  end

  @role :admin
  def handle_event("save", %{"policy_entitlement" => params} = submitted, socket) do
    written = write(socket.assigns, params, submitted["confirmed"] == "true")

    {:noreply, socket |> assign(:unfunded, []) |> saved(written)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
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
            <h2>Which leave type, and when it is offered</h2>
          </header>
          <.input
            :if={!@entitlement}
            field={@form[:leave_type_id]}
            type="select"
            label="Leave type"
            prompt="Choose one"
            options={@leave_types}
          />
          <.input field={@form[:effective_from]} type="date" label="Offered from" />
          <.input
            field={@form[:granted_to]}
            type="date"
            label="Stops granting after (optional)"
          />
          <.input
            field={@form[:effective_to]}
            type="date"
            label="Stops being spendable after (optional)"
          />
        </section>

        <section>
          <header>
            <h2>What it grants</h2>
          </header>
          <.input
            field={@form[:amount_source]}
            type="select"
            label="Where the amount comes from"
            options={@choices.sources}
          />
          <p>
            A share of the public holiday calendar makes holidays ordinary working days, taken as
            leave. UK part-timers need it: otherwise those who don't work Mondays miss most bank
            holidays and fall short of the statutory 5.6 weeks.
          </p>
          <.input
            field={@form[:pro_rated_by_fte]}
            type="checkbox"
            label="Pro-rated by the hours they work"
          />
          <.input
            field={@form[:grant_amount]}
            type="text"
            label={amount_label(@types[@form[:leave_type_id].value], @form[:pro_rated_by_fte].value)}
          />
          <.input
            field={@form[:grant_period]}
            type="select"
            label="Granted each"
            prompt="not granted"
            options={@choices.periods}
          />
          <.input
            field={@form[:grant_basis]}
            type="select"
            label="Reckoned from"
            prompt="not granted"
            options={@choices.bases}
          />
          <.input
            field={@form[:grant_timing]}
            type="select"
            label="How it arrives"
            prompt="not granted"
            options={@choices.timings}
          />
          <.input
            field={@form[:suspension_allowance_weeks]}
            type="text"
            label="Unpaid leave allowance (weeks)"
          />
          <p>
            Leave that suspends accrual still accrues for this many of the person's weeks each period.
          </p>
        </section>

        <section>
          <header>
            <h2>How long a new starter waits</h2>
          </header>
          <.input
            field={@form[:qualifying_months]}
            type="number"
            label="Months' service before it is first granted (optional)"
          />
          <p>
            For a fixed amount reckoned from their start date. Its periods then run from that many
            months after the start date.
          </p>
          <.input
            field={@form[:takeable_after_months]}
            type="number"
            label="Months' service before it can be taken (optional)"
          />
          <p>
            Left empty, it can be taken from their start date, going negative before anything is
            granted.
          </p>
        </section>

        <section>
          <header>
            <h2>What becomes of it</h2>
          </header>
          <.input
            field={@form[:expiry_rule]}
            type="select"
            label="Rollover"
            options={@choices.rules}
          />
          <.input field={@form[:rollover_cap]} type="text" label="Cap, where it rolls over to one" />
          <.input
            field={@form[:expiry_window_days]}
            type="number"
            label="Days before it lapses, where it lapses on a window"
          />
        </section>

        <section :if={@unfunded != []}>
          <header>
            <h2>Leave already booked would go unpaid for</h2>
          </header>
          <p>
            What these days draw on lapses before them. Saving anyway leaves each person's balance
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
    </Layouts.app>
    """
  end

  defp amending(:new, _policy, _params), do: {:ok, nil}
  defp amending(:edit, policy, %{"id" => id}), do: Policies.fetch_entitlement(policy, id)

  defp opened(socket, policy, {:ok, entitlement}) do
    {:ok, organisation} = Org.fetch_organisation(policy.organisation_id)
    offered = Policies.leave_types_offered(policy.organisation_id)

    # The picker offers only what is still offered, but the amount label names the unit of the type
    # this entitlement is already on, which may be one that has since been withdrawn.
    types = Policies.leave_types(policy.organisation_id)

    socket =
      socket
      |> assign(:page_title, title(entitlement))
      |> assign(:title, title(entitlement))
      |> assign(:policy, policy)
      |> assign(:entitlement, entitlement)
      |> assign(:leave_types, Enum.map(offered, &{Wording.leave_type(&1), &1.id}))
      |> assign(:types, Map.new(types, &{&1.id, &1}))
      |> assign(:choices, choices())
      |> assign(:unfunded, [])

    assign(socket, :form, to_form(change(socket.assigns, opening(entitlement, organisation))))
  end

  defp opened(socket, policy, :error) do
    socket
    |> put_flash(:error, "That entitlement is not on this policy.")
    |> push_navigate(to: ~p"/settings/policies/#{policy}")
  end

  defp unknown(socket) do
    socket
    |> put_flash(:error, "That policy is not on record.")
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
  # before that date grants anything anyway.
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

  # The amount is in the leave type's own unit, and is a full-time figure only where it is
  # pro-rated, so the label says so once both are chosen.
  defp amount_label(type, pro_rated), do: "Amount#{counted_in(type)}#{at_full_time(pro_rated)}"

  defp counted_in(nil), do: ""
  defp counted_in(type), do: " in #{type.unit}"

  defp at_full_time(pro_rated) do
    case Form.normalize_value("checkbox", pro_rated) do
      true -> ", at 1.0 FTE"
      false -> ""
    end
  end

  defp choices do
    %{sources: @sources, bases: @bases, periods: @periods, timings: @timings, rules: @rules}
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
      "Leave has been taken against this entitlement, so only when it stops granting and being " <>
        "spendable can change, or its unpaid leave allowance go up. To change its terms, stop it " <>
        "granting and add another."
    )
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
