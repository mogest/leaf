defmodule LeafWeb.PoliciesLive do
  @moduledoc """
  The named sets of entitlements people are put on.

  A policy is what makes somebody an employee or a contractor here — there is no other distinction
  — so this list is the shape of the organisation's arrangements.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Policies

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Leave policies") |> listed()}
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("offer", %{"id" => id}, socket) do
    {:noreply, offer(socket, Policies.fetch_leave_policy(id))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <h1>Leave policies</h1>
        <.link class="button" navigate={~p"/settings/policies/new"}>Add</.link>
      </header>

      <Parts.settings_nav here="policies" />

      <section>
        <header>
          <h2>What people can be put on</h2>
        </header>
        <div :if={@policies != []}>
          <table>
            <thead>
              <tr>
                <th scope="col">Name</th>
                <th scope="col">Entitlements</th>
                <th scope="col">Standing</th>
                <td></td>
              </tr>
            </thead>
            <tbody>
              <tr :for={policy <- @policies} data-tone={policy.tone}>
                <th scope="row"><.link navigate={policy.path}>{policy.name}</.link></th>
                <td>{policy.entitlements}</td>
                <td>{policy.offering}</td>
                <td>
                  <Parts.row_menu id={"policy-#{policy.id}"} label={policy.name}>
                    <button type="button" phx-click="offer" phx-value-id={policy.id}>
                      {policy.action}
                    </button>
                  </Parts.row_menu>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@policies == []}>No policies yet.</p>
      </section>
    </Layouts.app>
    """
  end

  defp listed(socket) do
    policies = Policies.leave_policies(socket.assigns.current_person.organisation_id)

    assign(socket, :policies, Enum.map(policies, &row(&1, socket.assigns.zone)))
  end

  defp row(policy, zone) do
    %{
      id: policy.id,
      name: policy.name,
      path: ~p"/settings/policies/#{policy}",
      entitlements: counted(policy.entitlements),
      offering: Wording.offering(policy, zone),
      tone: Wording.tone(policy),
      action: action(policy)
    }
  end

  defp action(%{archived_at: nil}), do: "Withdraw"
  defp action(_policy), do: "Use again"

  defp offer(socket, {:ok, policy}) do
    offered(socket, toggled(policy, socket.assigns.current_person))
  end

  defp offer(socket, :error), do: put_flash(socket, :error, "That policy is not on record.")

  defp toggled(%{archived_at: nil} = policy, actor), do: Policies.withdraw(policy, actor)
  defp toggled(policy, actor), do: Policies.reoffer(policy, actor)

  defp offered(socket, {:ok, %{archived_at: nil} = policy}) do
    socket |> put_flash(:info, "#{policy.name} is in use again.") |> listed()
  end

  defp offered(socket, {:ok, policy}) do
    socket
    |> put_flash(:info, "#{policy.name} is withdrawn. Whoever is already on it stays on it.")
    |> listed()
  end

  defp offered(socket, {:error, _changeset}),
    do: put_flash(socket, :error, "That would not save.")

  defp counted(entitlements) do
    named(length(Enum.uniq_by(entitlements, & &1.leave_type_id)))
  end

  defp named(0), do: "nothing yet"
  defp named(1), do: "one leave type"
  defp named(count), do: "#{count} leave types"
end
