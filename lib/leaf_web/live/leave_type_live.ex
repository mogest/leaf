defmodule LeafWeb.LeaveTypeLive do
  @moduledoc """
  Amending one leave type.

  Changing the unit changes what every amount already recorded against it means, so it is here
  rather than inline on the list, where it would be a click away from an accident.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Changeset
  alias Leaf.Policies

  @units [{"hours", "hours"}, {"days", "days"}]

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    case Policies.fetch_leave_type(id) do
      {:ok, leave_type} -> {:ok, opened(socket, leave_type)}
      :error -> {:ok, unknown(socket)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"leave_type" => params}, socket) do
    changeset = Changeset.change(socket.assigns.leave_type, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save", %{"leave_type" => params}, socket) do
    written =
      Policies.update_leave_type(socket.assigns.leave_type, socket.assigns.current_person, params)

    {:noreply, saved(socket, written)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <nav aria-label="Breadcrumb">
          <.link navigate={~p"/settings/leave-types"}>Leave types</.link>
        </nav>
        <h1>{@leave_type.name}</h1>
        <p :if={@leave_type.archived_at}>{withdrawn(@leave_type)}</p>
      </header>

      <.form id="leave-type" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:unit]} type="select" label="Counted in" options={@units} />
          <.input field={@form[:suspends_accrual]} type="checkbox" label="Suspends accrual" />
          <.input field={@form[:position]} type="number" label="Order" />
          <.input field={@form[:payroll_code]} type="text" label="Payroll code" />
        </section>

        <footer>
          <p>Changing the unit changes what every amount already recorded means.</p>
          <button class="button" type="submit">Save</button>
          <.link navigate={~p"/settings/leave-types"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp opened(socket, leave_type) do
    socket
    |> assign(:page_title, leave_type.name)
    |> assign(:leave_type, leave_type)
    |> assign(:units, @units)
    |> assign(:form, to_form(Changeset.change(leave_type, %{})))
  end

  defp unknown(socket) do
    socket
    |> put_flash(:error, "That leave type is not on record.")
    |> push_navigate(to: ~p"/settings/leave-types")
  end

  defp withdrawn(leave_type) do
    "Not offered in new configuration since #{Wording.date(DateTime.to_date(leave_type.archived_at))}. " <>
      "Policies that already include it go on granting it."
  end

  defp saved(socket, {:ok, _leave_type}) do
    socket
    |> put_flash(:info, "Saved.")
    |> push_navigate(to: ~p"/settings/leave-types")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
