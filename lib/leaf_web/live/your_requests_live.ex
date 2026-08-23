defmodule LeafWeb.YourRequestsLive do
  @moduledoc """
  Everything you have ever asked for, and what can still be done about each of it.

  Which of them you may still change is `Leaf.Leave`'s to say, not this page's: it asks, and shows
  the buttons for the answer it gets.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave
  alias Leaf.People

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Your requests") |> listed()}
  end

  @impl Phoenix.LiveView
  @role :member
  def handle_event("cancel", %{"id" => id}, socket) do
    {:ok, request} = Leave.fetch_request(id)

    {:noreply,
     socket |> cancelled(Leave.cancel(request, socket.assigns.current_person)) |> listed()}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="your-requests" viewer={@viewer}>
      <header>
        <h1>Your requests</h1>
        <.link class="button" navigate={~p"/leave/new"}>Request leave</.link>
      </header>

      <Parts.requests requests={@requests}>
        <:empty>You have not asked for any leave yet.</:empty>
        <:actions :let={request}>
          <.link :if={request.revisable?} navigate={~p"/leave/#{request.id}/amend"}>Edit</.link>
          <button
            :if={request.revisable?}
            type="button"
            phx-click="cancel"
            phx-value-id={request.id}
            data-confirm="Give this leave back? The request is cancelled and what it drew returned."
          >
            Cancel
          </button>
        </:actions>
      </Parts.requests>
    </Layouts.app>
    """
  end

  defp listed(socket) do
    person = socket.assigns.current_person
    today = Date.utc_today()
    manager = manager(person)

    assign(
      socket,
      :requests,
      Enum.map(Leave.requests(person), &shown(&1, person, today, manager))
    )
  end

  defp shown(request, person, today, manager) do
    request
    |> Wording.filed(today, manager)
    |> Map.put(:revisable?, Leave.revisable?(request, person))
  end

  defp manager(person) do
    case People.fetch_manager(person) do
      {:ok, manager} -> manager.name
      :error -> nil
    end
  end

  defp cancelled(socket, {:ok, _request}),
    do: put_flash(socket, :info, "The request is cancelled.")

  defp cancelled(socket, {:error, :forbidden}) do
    put_flash(socket, :error, "That is not yours to cancel.")
  end

  defp cancelled(socket, {:error, _changeset}) do
    put_flash(socket, :error, "The request would not cancel.")
  end
end
