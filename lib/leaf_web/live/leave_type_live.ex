defmodule LeafWeb.LeaveTypeLive do
  @moduledoc """
  Adding a leave type, and amending one.

  Changing the unit changes what every amount already recorded against it means, so it is here
  rather than inline on the list, where it would be a click away from an accident.
  """

  use LeafWeb, :live_view

  on_mount {LeafWeb.SignIn, :admin}

  alias Leaf.Changeset
  alias Leaf.Org
  alias Leaf.Policies

  @units [{"hours", "hours"}, {"days", "days"}]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case amending(socket.assigns.live_action, params) do
      {:ok, leave_type} -> {:ok, opened(socket, leave_type)}
      :error -> {:ok, unknown(socket)}
    end
  end

  @impl Phoenix.LiveView
  @role :admin
  def handle_event("validate", %{"leave_type" => params}, socket) do
    changeset = change(socket.assigns.leave_type, socket.assigns.organisation, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @role :admin
  def handle_event("save", %{"leave_type" => params}, socket) do
    {:noreply, saved(socket, write(socket.assigns, params))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <nav aria-label="Breadcrumb">
          <.link navigate={~p"/settings/leave-types"}>Leave types</.link>
        </nav>
        <h1>{@page_title}</h1>
        <p :if={@leave_type && @leave_type.archived_at}>{withdrawn(@leave_type, @zone)}</p>
      </header>

      <.form id="leave-type" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:unit]} type="select" label="Counted in" options={@units} />
          <.input field={@form[:suspends_accrual]} type="checkbox" label="Suspends accrual" />
          <.input field={@form[:needs_approval]} type="checkbox" label="Needs approval" />
          <.input field={@form[:position]} type="number" label="Order" />
          <.input field={@form[:payroll_code]} type="text" label="Payroll code" />
        </section>

        <footer>
          <p :if={@leave_type}>Changing the unit changes what every amount already recorded means.</p>
          <button class="button" type="submit">Save</button>
          <.link navigate={~p"/settings/leave-types"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp amending(:new, _params), do: {:ok, nil}
  defp amending(:edit, %{"id" => id}), do: Policies.fetch_leave_type(id)

  defp opened(socket, leave_type) do
    {:ok, organisation} = Org.fetch_organisation(socket.assigns.current_person.organisation_id)

    socket
    |> assign(:page_title, title(leave_type))
    |> assign(:leave_type, leave_type)
    |> assign(:organisation, organisation)
    |> assign(:units, @units)
    |> assign(
      :form,
      to_form(change(leave_type, organisation, defaults(leave_type, organisation)))
    )
  end

  defp unknown(socket) do
    socket
    |> put_flash(:error, "That leave type is not on record.")
    |> push_navigate(to: ~p"/settings/leave-types")
  end

  defp title(nil), do: "Add a leave type"
  defp title(leave_type), do: leave_type.name

  defp defaults(nil, organisation),
    do: %{"position" => length(Policies.leave_types(organisation.id)) + 1}

  defp defaults(_leave_type, _organisation), do: %{}

  defp change(nil, organisation, params), do: Policies.change_leave_type(organisation, params)
  defp change(leave_type, _organisation, params), do: Changeset.change(leave_type, params)

  defp write(%{leave_type: nil} = assigns, params) do
    Policies.create_leave_type(assigns.organisation, assigns.current_person, params)
  end

  defp write(assigns, params) do
    Policies.update_leave_type(assigns.leave_type, assigns.current_person, params)
  end

  defp withdrawn(leave_type, zone) do
    "Not offered in new configuration since #{Wording.date(leave_type.archived_at, zone)}. " <>
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
