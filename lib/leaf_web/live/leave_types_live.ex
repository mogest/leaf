defmodule LeafWeb.LeaveTypesLive do
  @moduledoc """
  The kinds of leave the organisation offers, and adding another.

  A type's unit is what every amount measuring it is counted in; how it is granted belongs to the
  policies that include it, so none of that is here. A type stops being offered by being archived,
  which takes it out of the pickers that set up new entitlements and balance entries and leaves
  everything already drawing on it alone — a policy stops granting a type by closing its
  entitlement, not here.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Org
  alias Leaf.Policies

  @units [{"hours", "hours"}, {"days", "days"}]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)

    {:ok,
     socket
     |> assign(:page_title, "Leave types")
     |> assign(:organisation, organisation)
     |> assign(:units, @units)
     |> listed()
     |> blank()}
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"leave_type" => params}, socket) do
    changeset = Policies.change_leave_type(socket.assigns.organisation, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save", %{"leave_type" => params}, socket) do
    created =
      Policies.create_leave_type(
        socket.assigns.organisation,
        socket.assigns.current_person,
        params
      )

    {:noreply, saved(socket, created)}
  end

  @role :admin
  def handle_event("offer", %{"id" => id}, socket) do
    {:noreply, offer(socket, Policies.fetch_leave_type(id))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <h1>Leave types</h1>
      </header>

      <Parts.settings_nav here="leave-types" />

      <section>
        <header>
          <h2>What the organisation offers</h2>
        </header>
        <div :if={@leave_types != []}>
          <table>
            <thead>
              <tr>
                <th scope="col">Order</th>
                <th scope="col">Name</th>
                <th scope="col">Counted in</th>
                <th scope="col">Standing</th>
                <td></td>
              </tr>
            </thead>
            <tbody>
              <tr :for={leave_type <- @leave_types} data-tone={leave_type.tone}>
                <td>{leave_type.position}</td>
                <th scope="row"><.link navigate={leave_type.path}>{leave_type.name}</.link></th>
                <td>{leave_type.unit}</td>
                <td>{leave_type.offering}</td>
                <td>
                  <Parts.row_menu id={"leave-type-#{leave_type.id}"} label={leave_type.name}>
                    <button type="button" phx-click="offer" phx-value-id={leave_type.id}>
                      {leave_type.action}
                    </button>
                  </Parts.row_menu>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@leave_types == []}>No leave types yet.</p>
      </section>

      <.form id="new-leave-type" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Add a leave type</h2>
          </header>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:unit]} type="select" label="Counted in" options={@units} />
          <.input field={@form[:suspends_accrual]} type="checkbox" label="Suspends accrual" />
          <.input field={@form[:position]} type="number" label="Order" />
          <.input field={@form[:payroll_code]} type="text" label="Payroll code" />
        </section>

        <footer>
          <button class="button" type="submit">Add it</button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp listed(socket) do
    leave_types = Policies.leave_types(socket.assigns.organisation.id)

    socket
    |> assign(:leave_types, Enum.map(leave_types, &row(&1, socket.assigns.zone)))
    |> assign(:next, length(leave_types) + 1)
  end

  defp blank(socket) do
    changeset =
      Policies.change_leave_type(socket.assigns.organisation, %{
        "unit" => "hours",
        "position" => socket.assigns.next
      })

    assign(socket, :form, to_form(changeset))
  end

  defp row(leave_type, zone) do
    %{
      id: leave_type.id,
      name: leave_type.name,
      unit: to_string(leave_type.unit),
      position: leave_type.position,
      path: ~p"/settings/leave-types/#{leave_type}",
      offering: Wording.offering(leave_type, zone),
      tone: Wording.tone(leave_type),
      action: action(leave_type)
    }
  end

  defp action(%{archived_at: nil}), do: "Stop offering"
  defp action(_leave_type), do: "Offer again"

  defp offer(socket, {:ok, leave_type}) do
    offered(socket, toggled(leave_type, socket.assigns.current_person))
  end

  defp offer(socket, :error),
    do: put_flash(socket, :error, "That leave type is not on record.")

  defp toggled(%{archived_at: nil} = leave_type, actor), do: Policies.withdraw(leave_type, actor)
  defp toggled(leave_type, actor), do: Policies.reoffer(leave_type, actor)

  defp offered(socket, {:ok, %{archived_at: nil} = leave_type}) do
    socket |> put_flash(:info, "#{leave_type.name} is offered again.") |> listed()
  end

  defp offered(socket, {:ok, leave_type}) do
    socket |> put_flash(:info, "#{leave_type.name} is no longer offered.") |> listed()
  end

  defp offered(socket, {:error, _changeset}),
    do: put_flash(socket, :error, "That would not save.")

  defp saved(socket, {:ok, leave_type}) do
    socket |> put_flash(:info, "#{leave_type.name} is offered.") |> listed() |> blank()
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
