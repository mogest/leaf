defmodule LeafWeb.EntitlementLive do
  @moduledoc """
  What one policy grants for one leave type, over one stretch of time.

  Every rule §4.5 lists is a field here, and which of them apply to each other is the changeset's
  to say rather than the form's: an amount that grants nothing wants no grant period, and an
  entitlement that never lapses wants no cap. The form offers them all and reports the refusal.
  """

  use LeafWeb, :live_view

  alias Leaf.Policies

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
    {:ok, policy} = Policies.fetch_leave_policy(params["policy_id"])
    entitlement = amending(socket.assigns.live_action, params)

    {:ok,
     socket
     |> assign(:page_title, title(socket.assigns.live_action))
     |> assign(:title, title(socket.assigns.live_action))
     |> assign(:policy, policy)
     |> assign(:entitlement, entitlement)
     |> assign(:leave_types, leave_types(policy))
     |> assign(:choices, choices())
     |> assign(:form, to_form(change(policy, entitlement, opening(entitlement))))}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"policy_entitlement" => params}, socket) do
    changeset = change(socket.assigns.policy, socket.assigns.entitlement, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"policy_entitlement" => params}, socket) do
    {:noreply, saved(socket, write(socket.assigns, params))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" current_person={@current_person}>
      <header>
        <h1>{@title}</h1>
        <.link navigate={~p"/settings/policies/#{@policy}"}>{@policy.name}</.link>
      </header>

      <.form id="entitlement" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Which leave type, and when it is offered</h2>
            <p>two entitlements for one type may not overlap</p>
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
            label="Stops granting after"
            placeholder="never"
          />
          <.input
            field={@form[:effective_to]}
            type="date"
            label="Stops being spendable after"
            placeholder="never"
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
          <.input field={@form[:grant_amount]} type="text" label="Amount, at 1.0 FTE" />
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
            field={@form[:pro_rated_by_fte]}
            type="checkbox"
            label="Pro-rated by the hours they work"
          />
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
          <.input field={@form[:allow_negative]} type="checkbox" label="May be taken in advance" />
          <.input
            field={@form[:excess_threshold]}
            type="text"
            label="Report a balance over"
            placeholder="no threshold"
          />
        </section>

        <footer>
          <button class="button" type="submit">Save</button>
          <.link navigate={~p"/settings/policies/#{@policy}"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp amending(:new, _params), do: nil

  defp amending(:edit, %{"id" => id}) do
    {:ok, entitlement} = Policies.fetch_entitlement(id)

    entitlement
  end

  defp title(:new), do: "Add an entitlement"
  defp title(:edit), do: "Amend an entitlement"

  # A leave type is settled when the entitlement is created: moving one to another type would
  # silently re-file everything already granted under it.
  defp change(policy, nil, params), do: Policies.change_entitlement(policy, nil, params)
  defp change(_policy, entitlement, params), do: Policies.change_entitlement(entitlement, params)

  defp opening(nil) do
    %{
      "amount_source" => "fixed",
      "grant_period" => "year",
      "grant_basis" => "employment_date",
      "grant_timing" => "daily",
      "pro_rated_by_fte" => "true",
      "expiry_rule" => "never",
      "allow_negative" => "false"
    }
  end

  defp opening(_entitlement), do: %{}

  defp leave_types(policy) do
    policy.organisation_id
    |> Policies.leave_types()
    |> Enum.filter(&is_nil(&1.archived_at))
    |> Enum.map(&{Wording.leave_type(&1), &1.id})
  end

  defp choices do
    %{sources: @sources, bases: @bases, periods: @periods, timings: @timings, rules: @rules}
  end

  defp write(%{entitlement: nil} = assigns, params) do
    created(assigns, params, params["leave_type_id"])
  end

  defp write(assigns, params) do
    Policies.update_entitlement(assigns.entitlement, assigns.current_person, params)
  end

  # An unchosen leave type is a blank the changeset already knows how to refuse, so it is handed
  # back rather than looked up.
  defp created(assigns, params, id) when id in [nil, ""] do
    {:error, change(assigns.policy, nil, params)}
  end

  defp created(assigns, params, id) do
    {:ok, leave_type} = Policies.fetch_leave_type(id)

    Policies.create_entitlement(assigns.policy, leave_type, assigns.current_person, params)
  end

  defp saved(socket, {:ok, _entitlement}) do
    socket
    |> put_flash(:info, "Saved.")
    |> push_navigate(to: ~p"/settings/policies/#{socket.assigns.policy}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
