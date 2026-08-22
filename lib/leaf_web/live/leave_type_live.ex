defmodule LeafWeb.LeaveTypeLive do
  @moduledoc """
  Amending one leave type.

  Changing the unit changes what every amount already recorded against it means, so it is here
  rather than inline on the list, where it would be a click away from an accident.
  """

  use LeafWeb, :live_view

  alias Leaf.Policies

  @units [{"hours", "hours"}, {"days", "days"}]

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    {:ok, leave_type} = Policies.fetch_leave_type(id)

    {:ok,
     socket
     |> assign(:page_title, leave_type.name)
     |> assign(:leave_type, leave_type)
     |> assign(:units, @units)
     |> assign(:form, to_form(Policies.change_leave_type(leave_type, %{})))}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"leave_type" => params}, socket) do
    changeset = Policies.change_leave_type(socket.assigns.leave_type, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"leave_type" => params}, socket) do
    written =
      Policies.update_leave_type(socket.assigns.leave_type, socket.assigns.current_person, params)

    {:noreply, saved(socket, written)}
  end

  def handle_event("archive", _params, socket) do
    leave_type = socket.assigns.leave_type
    attrs = %{archived_at: archived_at(leave_type)}

    {:noreply,
     written(socket, Policies.update_leave_type(leave_type, socket.assigns.current_person, attrs))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" viewer={@viewer}>
      <header>
        <h1>{@leave_type.name}</h1>
        <.link navigate={~p"/settings/leave-types"}>Leave types</.link>
      </header>

      <.form id="leave-type" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>What it is</h2>
            <p>changing the unit changes what every amount already recorded means</p>
          </header>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:unit]} type="select" label="Counted in" options={@units} />
          <.input field={@form[:position]} type="number" label="Order" />
          <p>{standing(@leave_type)}</p>
        </section>

        <footer>
          <button class="button" type="submit">Save</button>
          <button type="button" phx-click="archive">{action(@leave_type)}</button>
          <.link navigate={~p"/settings/leave-types"}>Cancel</.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  defp standing(%{archived_at: nil}), do: "Offered."

  defp standing(leave_type),
    do: "Withdrawn #{Wording.date(DateTime.to_date(leave_type.archived_at))}."

  defp action(%{archived_at: nil}), do: "Withdraw"
  defp action(_leave_type), do: "Offer again"

  defp archived_at(%{archived_at: nil}), do: DateTime.truncate(DateTime.utc_now(), :second)
  defp archived_at(_leave_type), do: nil

  defp written(socket, {:ok, leave_type}) do
    socket |> assign(:leave_type, leave_type) |> put_flash(:info, "Saved.")
  end

  defp written(socket, {:error, _changeset}),
    do: put_flash(socket, :error, "That would not save.")

  defp saved(socket, {:ok, _leave_type}) do
    socket
    |> put_flash(:info, "Saved.")
    |> push_navigate(to: ~p"/settings/leave-types")
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
