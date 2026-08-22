defmodule LeafWeb.PoliciesLive do
  @moduledoc """
  The named sets of entitlements people are put on, and adding another.

  A policy is what makes somebody an employee or a contractor here — there is no other distinction
  — so this list is the shape of the organisation's arrangements.
  """

  use LeafWeb, :live_view

  alias Leaf.Org
  alias Leaf.Policies

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)

    {:ok,
     socket
     |> assign(:page_title, "Leave policies")
     |> assign(:organisation, organisation)
     |> assign(:form, to_form(Policies.change_leave_policy(organisation, %{})))
     |> listed()}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"leave_policy" => params}, socket) do
    changeset = Policies.change_leave_policy(socket.assigns.organisation, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"leave_policy" => params}, socket) do
    created =
      Policies.create_leave_policy(
        socket.assigns.organisation,
        socket.assigns.current_person,
        params
      )

    {:noreply, saved(socket, created)}
  end

  def handle_event("archive", %{"id" => id}, socket) do
    {:ok, policy} = Policies.fetch_leave_policy(id)
    attrs = %{archived_at: archived_at(policy)}
    written = Policies.update_leave_policy(policy, socket.assigns.current_person, attrs)

    {:noreply, socket |> written(written) |> listed()}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <h1>Leave policies</h1>
      </header>

      <Parts.settings_nav here="policies" />

      <section>
        <header>
          <h2>What people can be put on</h2>
        </header>
        <table>
          <thead>
            <tr>
              <th scope="col">Name</th>
              <th scope="col">Entitlements</th>
              <th scope="col">Standing</th>
              <th scope="col"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={policy <- @policies} data-tone={policy.tone}>
              <th scope="row"><.link navigate={policy.path}>{policy.name}</.link></th>
              <td>{policy.entitlements}</td>
              <td>{policy.standing}</td>
              <td>
                <button type="button" phx-click="archive" phx-value-id={policy.id}>
                  {policy.action}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@policies == []}>No policies yet.</p>
      </section>

      <.form id="new-policy" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Add a policy</h2>
            <p>what it grants is set on the policy itself</p>
          </header>
          <.input field={@form[:name]} type="text" label="Name" />
        </section>

        <footer>
          <button class="button" type="submit">Add it</button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp listed(socket) do
    policies = Policies.leave_policies(socket.assigns.organisation.id)

    assign(socket, :policies, Enum.map(policies, &row/1))
  end

  defp row(policy) do
    %{
      id: policy.id,
      name: policy.name,
      path: ~p"/settings/policies/#{policy}",
      entitlements: counted(Policies.entitlements(policy.id)),
      standing: standing(policy),
      action: action(policy),
      tone: tone(policy)
    }
  end

  defp counted(entitlements) do
    named(length(Enum.uniq_by(entitlements, & &1.leave_type_id)))
  end

  defp named(0), do: "nothing yet"
  defp named(1), do: "one leave type"
  defp named(count), do: "#{count} leave types"

  defp standing(%{archived_at: nil}), do: "in use"
  defp standing(policy), do: "withdrawn #{Wording.date(DateTime.to_date(policy.archived_at))}"

  defp action(%{archived_at: nil}), do: "Withdraw"
  defp action(_policy), do: "Use again"

  defp tone(%{archived_at: nil}), do: nil
  defp tone(_policy), do: "past"

  defp archived_at(%{archived_at: nil}), do: DateTime.truncate(DateTime.utc_now(), :second)
  defp archived_at(_policy), do: nil

  defp written(socket, {:ok, _policy}), do: put_flash(socket, :info, "Saved.")

  defp written(socket, {:error, _changeset}),
    do: put_flash(socket, :error, "That would not save.")

  defp saved(socket, {:ok, policy}) do
    push_navigate(socket, to: ~p"/settings/policies/#{policy}")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
