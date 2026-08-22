defmodule LeafWeb.LeaveTypesLive do
  @moduledoc """
  The kinds of leave the organisation offers, and adding another.

  A type's unit is what every amount measuring it is counted in; how it is granted belongs to the
  policies that include it, so none of that is here. Withdrawing one is archiving, because what it
  granted has to keep making sense.
  """

  use LeafWeb, :live_view

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
  def handle_event("validate", %{"leave_type" => params}, socket) do
    changeset = Policies.change_leave_type(socket.assigns.organisation, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"leave_type" => params}, socket) do
    created =
      Policies.create_leave_type(
        socket.assigns.organisation,
        socket.assigns.current_person,
        params
      )

    {:noreply, saved(socket, created)}
  end

  def handle_event("archive", %{"id" => id}, socket) do
    {:ok, leave_type} = Policies.fetch_leave_type(id)
    attrs = %{archived_at: archived_at(leave_type)}

    written = Policies.update_leave_type(leave_type, socket.assigns.current_person, attrs)

    {:noreply, socket |> written(written) |> listed()}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="settings" current_person={@current_person}>
      <header>
        <h1>Leave types</h1>
      </header>

      <Parts.settings_nav here="leave-types" />

      <section>
        <header>
          <h2>What the organisation offers</h2>
          <p>in the order they are shown in</p>
        </header>
        <table>
          <thead>
            <tr>
              <th scope="col">Order</th>
              <th scope="col">Name</th>
              <th scope="col">Counted in</th>
              <th scope="col">Standing</th>
              <th scope="col"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={leave_type <- @leave_types} data-tone={leave_type.tone}>
              <td>{leave_type.position}</td>
              <th scope="row"><.link navigate={leave_type.path}>{leave_type.name}</.link></th>
              <td>{leave_type.unit}</td>
              <td>{leave_type.standing}</td>
              <td>
                <button type="button" phx-click="archive" phx-value-id={leave_type.id}>
                  {leave_type.action}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@leave_types == []}>No leave types yet.</p>
      </section>

      <.form id="new-leave-type" for={@form} phx-change="validate" phx-submit="save">
        <section>
          <header>
            <h2>Add a leave type</h2>
          </header>
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:unit]} type="select" label="Counted in" options={@units} />
          <.input field={@form[:position]} type="number" label="Order" />
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
    |> assign(:leave_types, Enum.map(leave_types, &row/1))
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

  defp row(leave_type) do
    %{
      id: leave_type.id,
      name: leave_type.name,
      unit: to_string(leave_type.unit),
      position: leave_type.position,
      path: ~p"/settings/leave-types/#{leave_type}",
      standing: standing(leave_type),
      action: action(leave_type),
      tone: tone(leave_type)
    }
  end

  defp standing(%{archived_at: nil}), do: "offered"

  defp standing(leave_type),
    do: "withdrawn #{Wording.date(DateTime.to_date(leave_type.archived_at))}"

  defp action(%{archived_at: nil}), do: "Withdraw"
  defp action(_leave_type), do: "Offer again"

  defp tone(%{archived_at: nil}), do: nil
  defp tone(_leave_type), do: "past"

  defp archived_at(%{archived_at: nil}), do: DateTime.truncate(DateTime.utc_now(), :second)
  defp archived_at(_leave_type), do: nil

  defp written(socket, {:ok, _leave_type}), do: put_flash(socket, :info, "Saved.")

  defp written(socket, {:error, _changeset}),
    do: put_flash(socket, :error, "That would not save.")

  defp saved(socket, {:ok, leave_type}) do
    socket |> put_flash(:info, "#{leave_type.name} is offered.") |> listed() |> blank()
  end

  defp saved(socket, {:error, changeset}) do
    assign(socket, :form, to_form(changeset, action: :validate))
  end
end
