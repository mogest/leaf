defmodule LeafWeb.PolicyLive do
  @moduledoc """
  One policy: its name, and what it grants for each leave type over each stretch of time.

  Two entitlements for one leave type may not overlap, so succeeding one means closing the old
  window rather than only opening a new one. Each is said in words here, because what a row of
  enumerations means is the thing an administrator is actually checking.
  """

  use LeafWeb, :live_view

  alias Leaf.Policies

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    {:ok, policy} = Policies.fetch_leave_policy(id)

    {:ok,
     socket
     |> assign(:page_title, policy.name)
     |> assign(:policy, policy)
     |> assign(:form, to_form(Policies.change_leave_policy(policy, %{})))
     |> listed()}
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"leave_policy" => params}, socket) do
    changeset = Policies.change_leave_policy(socket.assigns.policy, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save", %{"leave_policy" => params}, socket) do
    written =
      Policies.update_leave_policy(socket.assigns.policy, socket.assigns.current_person, params)

    {:noreply, saved(socket, written)}
  end

  @role :admin
  def handle_event("archive", _params, socket) do
    policy = socket.assigns.policy
    attrs = %{archived_at: archived_at(policy)}

    {:noreply,
     saved(socket, Policies.update_leave_policy(policy, socket.assigns.current_person, attrs))}
  end

  @role :admin
  def handle_event("remove", %{"id" => id}, socket) do
    {:noreply, remove(socket, Policies.fetch_entitlement(socket.assigns.policy, id))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <.link navigate={~p"/settings/policies"}>Leave policies</.link>
        <h1>{@policy.name}</h1>
      </header>

      <section>
        <header>
          <h2>What it grants</h2>
          <.link class="add" navigate={~p"/settings/policies/#{@policy}/entitlements/new"}>
            Add
          </.link>
        </header>
        <ol :if={@entitlements != []}>
          <li :for={entitlement <- @entitlements}>
            <p>
              <span>{entitlement.leave_type}</span>
              <span>{entitlement.window}</span>
            </p>
            <p>{entitlement.grant}</p>
            <p>{entitlement.expiry}</p>
            <div>
              <.link navigate={entitlement.path}>Edit</.link>
              <button
                type="button"
                phx-click="remove"
                phx-value-id={entitlement.id}
                data-confirm="Remove this outright? One that ran and is over should be closed with an end date instead."
              >
                Remove
              </button>
            </div>
          </li>
        </ol>
        <p :if={@entitlements == []}>This policy grants nothing yet.</p>
      </section>

      <section>
        <header>
          <h2>Whether it is in use</h2>
          <button type="button" phx-click="archive">{action(@policy)}</button>
        </header>
        <p>{standing(@policy)}</p>
      </section>

      <.form id="policy" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>The policy itself</h2>
          </header>
          <.input field={@form[:name]} type="text" label="Name" />
        </section>

        <footer>
          <button class="button" type="submit">Save</button>
          <.link navigate={~p"/settings/policies"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp listed(socket) do
    entitlements = Policies.entitlements(socket.assigns.policy.id)

    assign(socket, :entitlements, Enum.map(entitlements, &row(&1, socket.assigns.policy)))
  end

  defp row(entitlement, policy) do
    %{
      id: entitlement.id,
      leave_type: entitlement.leave_type.name,
      window: window(entitlement),
      grant: grant(entitlement),
      expiry: lapsing(entitlement),
      path: ~p"/settings/policies/#{policy}/entitlements/#{entitlement}"
    }
  end

  defp window(entitlement) do
    [
      "offered from #{Wording.date(entitlement.effective_from)}",
      granting_to(entitlement.granted_to),
      until(entitlement.effective_to)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp granting_to(nil), do: nil
  defp granting_to(date), do: "granting until #{Wording.date(date)}"

  defp until(nil), do: nil
  defp until(date), do: "spendable until #{Wording.date(date)}"

  defp grant(%{amount_source: :none}), do: "Grants nothing — leave of this type is recorded only."

  defp grant(entitlement) do
    "#{amount(entitlement)}, #{anchored(entitlement)}, #{landing(entitlement)}#{pro_rated(entitlement)}."
  end

  defp amount(%{amount_source: :public_holidays} = entitlement) do
    "Their share of the public holidays on their calendar each #{entitlement.grant_period}"
  end

  defp amount(entitlement) do
    "#{figure(entitlement, entitlement.grant_amount)} each #{entitlement.grant_period}"
  end

  defp figure(entitlement, amount), do: Wording.figure(amount, entitlement.leave_type.unit)

  defp anchored(%{grant_basis: :employment_date}), do: "reckoned from their start date"
  defp anchored(%{grant_basis: :birthday}), do: "reckoned from their birthday"
  defp anchored(%{grant_basis: :calendar_year}), do: "reckoned from the calendar year"
  defp anchored(%{grant_basis: :organisation_year}), do: "reckoned from the financial year"

  defp landing(%{grant_timing: :daily}), do: "accruing day by day"
  defp landing(_entitlement), do: "landing whole when the period opens"

  defp pro_rated(%{pro_rated_by_fte: true}), do: ", pro-rated by the hours they work"
  defp pro_rated(_entitlement), do: ""

  defp lapsing(%{expiry_rule: :never}), do: "Rolls over indefinitely"

  defp lapsing(%{expiry_rule: :cap} = entitlement) do
    "Rolls over up to #{figure(entitlement, entitlement.rollover_cap)}"
  end

  defp lapsing(%{expiry_rule: :grant_period_end}), do: "Lapses at the end of each period"

  defp lapsing(%{expiry_rule: :window} = entitlement) do
    "Lapses #{entitlement.expiry_window_days} days after it lands"
  end

  defp standing(%{archived_at: nil}), do: "In use, and offered when somebody is put on a policy."

  defp standing(policy) do
    "Withdrawn #{Wording.date(DateTime.to_date(policy.archived_at))}. " <>
      "Nobody new goes on it; whoever is already on it stays, and goes on being granted what it says."
  end

  defp action(%{archived_at: nil}), do: "Withdraw"
  defp action(_policy), do: "Use again"

  defp archived_at(%{archived_at: nil}), do: DateTime.truncate(DateTime.utc_now(), :second)
  defp archived_at(_policy), do: nil

  defp saved(socket, {:ok, policy}) do
    socket
    |> assign(:policy, policy)
    |> assign(:form, to_form(Policies.change_leave_policy(policy, %{})))
    |> put_flash(:info, "Saved.")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end

  defp remove(socket, :error) do
    put_flash(socket, :error, "That entitlement is not on this policy.")
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
      "Leave has been taken against that entitlement. Stop it granting instead of removing it."
    )
  end

  defp removed(socket, {:error, _changeset}) do
    put_flash(socket, :error, "That would not come off the policy.")
  end
end
