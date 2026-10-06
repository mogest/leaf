defmodule LeafWeb.YourRequestsLive do
  @moduledoc """
  Everything you have ever asked for, and what can still be done about each of it.

  Which of them you may still change is `Leaf.Leave`'s to say, not this page's: it asks, and a row
  it says yes to opens onto its amendment, with cancelling it in the row's menu.
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
  def handle_event("cancel-request", %{"id" => id}, socket) do
    {:noreply, socket |> Parts.cancel_request(id) |> listed()}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="your-requests" viewer={@viewer}>
      <header>
        <h1>Your requests</h1>
        <.link class="button" navigate={~p"/leave/new"}>Request leave</.link>
      </header>

      <Parts.requests requests={@requests} cancel>
        <:empty>You have not asked for any leave yet.</:empty>
      </Parts.requests>
    </Layouts.app>
    """
  end

  defp listed(socket) do
    person = socket.assigns.current_person
    today = People.today(person)
    manager = People.manager_name(person)

    assign(
      socket,
      :requests,
      Enum.map(Leave.requests(person), &shown(&1, person, today, manager))
    )
  end

  defp shown(request, person, today, manager) do
    request |> Wording.filed(today, manager) |> Parts.revisable(request, person)
  end
end
