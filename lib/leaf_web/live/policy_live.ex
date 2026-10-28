defmodule LeafWeb.PolicyLive do
  @moduledoc """
  One policy: what it grants for each leave type over each stretch of time.

  Two entitlements for one leave type may not overlap, so succeeding one means closing the old
  window rather than only opening a new one.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.People
  alias Leaf.Policies

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    case Policies.fetch_leave_policy(id) do
      {:ok, policy} -> {:ok, opened(socket, policy)}
      :error -> {:ok, unknown(socket)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("remove", %{"id" => id}, socket) do
    {:noreply, remove(socket, Policies.fetch_entitlement(socket.assigns.policy, id))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="policy" rail="settings" viewer={@viewer}>
      <header>
        <nav aria-label="Breadcrumb">
          <.link navigate={~p"/settings/policies"}>Leave policies</.link>
        </nav>
        <h1>{@policy.name}</h1>
        <p :if={@policy.archived_at}>{withdrawn(@policy, @zone)}</p>
        <.link class="button" navigate={~p"/settings/policies/#{@policy}/edit"}>Edit</.link>
      </header>

      <section>
        <header>
          <h2>Entitlements</h2>
          <.link class="add" navigate={~p"/settings/policies/#{@policy}/entitlements/new"}>
            Add
          </.link>
        </header>
        <div :if={@entitlements != []}>
          <table>
            <thead>
              <tr>
                <th scope="col">Leave type</th>
                <th scope="col">Amount</th>
                <th scope="col">Aligned to</th>
                <th scope="col">Arrives</th>
                <th scope="col">Unused</th>
                <td></td>
              </tr>
            </thead>
            <tbody>
              <tr :for={entitlement <- @entitlements}>
                <th scope="row">
                  <.link navigate={entitlement.path}>{entitlement.leave_type}</.link>
                  <small :if={entitlement.notes != ""}>{entitlement.notes}</small>
                </th>
                <%= if grant = entitlement.grant do %>
                  <td>{grant.amount} <small :if={grant.pro_rated}>{grant.pro_rated}</small></td>
                  <td>{grant.aligned} <small :if={grant.waiting}>{grant.waiting}</small></td>
                  <td>{grant.arrives} <small :if={grant.allowance}>{grant.allowance}</small></td>
                  <td>{grant.unused}</td>
                <% else %>
                  <td colspan="4">Recorded only</td>
                <% end %>
                <td>
                  <Parts.row_menu id={"entitlement-#{entitlement.id}"} label={entitlement.leave_type}>
                    <button
                      type="button"
                      phx-click="remove"
                      phx-value-id={entitlement.id}
                      data-confirm="Remove this entitlement? If it has been in use, set an end date instead so its history is kept."
                    >
                      Remove
                    </button>
                  </Parts.row_menu>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@entitlements == []}>This policy grants nothing yet.</p>
      </section>
    </Layouts.app>
    """
  end

  defp opened(socket, policy) do
    socket
    |> assign(:page_title, policy.name)
    |> assign(:policy, policy)
    |> listed()
  end

  defp unknown(socket) do
    socket
    |> put_flash(:error, "Policy not found.")
    |> push_navigate(to: ~p"/settings/policies")
  end

  defp listed(socket) do
    entitlements = Policies.entitlements(socket.assigns.policy.id)
    today = People.today(socket.assigns.current_person)

    assign(socket, :entitlements, Enum.map(entitlements, &row(&1, socket.assigns.policy, today)))
  end

  defp row(entitlement, policy, today) do
    %{
      id: entitlement.id,
      leave_type: entitlement.leave_type.name,
      notes: notes(entitlement, today),
      grant: grant(entitlement),
      path: ~p"/settings/policies/#{policy}/entitlements/#{entitlement}"
    }
  end

  defp notes(entitlement, today) do
    [
      starting(entitlement.effective_from, today),
      taken_after(entitlement.takeable_after_months),
      checked(entitlement.balance_check),
      granting_to(entitlement.granted_to),
      until(entitlement.effective_to)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp starting(date, today) do
    if Date.after?(date, today), do: "from #{Wording.date(date)}"
  end

  defp taken_after(nil), do: nil
  defp taken_after(months), do: "can be taken after #{months(months)}"

  defp checked(:off), do: nil
  defp checked(:today), do: "an administrator approves leave today's balance doesn't cover"
  defp checked(:projected), do: "an administrator approves leave the balance won't cover by then"

  defp granting_to(nil), do: nil
  defp granting_to(date), do: "stops granting after #{Wording.date(date)}"

  defp until(nil), do: nil
  defp until(date), do: "stops being spendable after #{Wording.date(date)}"

  defp months(months), do: Wording.figure(Decimal.new(months), :months)

  defp grant(%{amount_source: :none}), do: nil

  defp grant(entitlement) do
    %{
      amount: amount(entitlement),
      pro_rated: entitlement.pro_rated_by_fte && "pro-rated",
      aligned: aligned(entitlement.grant_basis),
      waiting: waiting(entitlement.qualifying_months),
      arrives: arrives(entitlement.grant_timing),
      allowance: allowance(entitlement.suspension_allowance_weeks),
      unused: unused(entitlement)
    }
  end

  defp amount(%{amount_source: :public_holidays}), do: "Public holidays"

  defp amount(entitlement) do
    "#{figure(entitlement, entitlement.grant_amount)} a #{entitlement.grant_period}"
  end

  defp figure(entitlement, amount), do: Wording.figure(amount, entitlement.leave_type.unit)

  defp aligned(:employment_date), do: "Start date"
  defp aligned(:birthday), do: "Birthday"
  defp aligned(:calendar_year), do: "Calendar year"
  defp aligned(:organisation_year), do: "Financial year"

  defp waiting(nil), do: nil
  defp waiting(months), do: "first granted after #{months(months)}"

  defp arrives(:daily), do: "Day by day, evenly over the period"
  defp arrives(:monthly), do: "Day by day, evenly over each month"
  defp arrives(:period_start), do: "Whole at period start"

  defp allowance(nil), do: nil
  defp allowance(weeks), do: "accrues through #{Wording.figure(weeks, :weeks)} unpaid"

  defp unused(%{expiry_rule: :never}), do: "Rolls over"

  defp unused(%{expiry_rule: :cap} = entitlement),
    do: "Rolls over up to #{figure(entitlement, entitlement.rollover_cap)}"

  defp unused(%{expiry_rule: :grant_period_end}), do: "Expires at period end"

  defp unused(%{expiry_rule: :window} = entitlement),
    do: "Expires #{entitlement.expiry_window_days} days after it's granted"

  defp withdrawn(policy, zone) do
    "Withdrawn #{Wording.date(policy.archived_at, zone)}. " <>
      "It can't be assigned to anyone new. People already on it keep it."
  end

  defp remove(socket, :error) do
    put_flash(socket, :error, "Entitlement not found.")
  end

  defp remove(socket, {:ok, entitlement}) do
    written = Policies.delete_entitlement(entitlement, socket.assigns.current_person)

    socket |> removed(written) |> listed()
  end

  defp removed(socket, {:ok, _entitlement}), do: put_flash(socket, :info, "Removed.")

  defp removed(socket, {:error, :drawn_on}) do
    put_flash(
      socket,
      :error,
      "Leave has been taken under this entitlement, so it can't be removed. " <>
        "Set \"Stops granting after\" instead."
    )
  end

  defp removed(socket, {:error, _changeset}) do
    put_flash(socket, :error, "Couldn't remove that.")
  end
end
