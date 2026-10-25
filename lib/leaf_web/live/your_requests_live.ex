defmodule LeafWeb.YourRequestsLive do
  @moduledoc """
  Everything you have asked for, a financial year at a time, and what can still be done about each.

  Which of them you may still change is `Leaf.Leave`'s to say, not this page's: it asks, and a row
  it says yes to opens onto its amendment, with cancelling it in the row's menu.
  """

  use LeafWeb, :live_view

  alias Ecto.Changeset
  alias Leaf.Leave
  alias Leaf.People

  @params %{year: :integer, leave_type: Ecto.UUID}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Your requests")}
  end

  # What does not read as a filter is left out, so the page reads as it does unfiltered.
  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    changeset = Changeset.cast({%{}, @params}, params, Map.keys(@params))
    asked = Map.drop(changeset.changes, Keyword.keys(changeset.errors))

    {:noreply, socket |> assign(:asked, asked) |> listed()}
  end

  @impl Phoenix.LiveView
  @role :member
  def handle_event("filter", %{"filter" => %{"leave_type" => leave_type}}, socket) do
    {:noreply, push_patch(socket, to: filtered(socket.assigns.asked[:year], leave_type))}
  end

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

      <.form :if={@leave_types != []} id="filter" for={@form} phx-change="filter">
        <.input
          field={@form[:leave_type]}
          type="select"
          label="Leave type"
          prompt="All leave types"
          options={@leave_types}
        />
      </.form>

      <Parts.requests requests={@requests} title={@span} cancel>
        <:steps><Parts.steps earlier={@earlier} later={@later} what="year" /></:steps>
        <:empty>No leave requests in this year.</:empty>
      </Parts.requests>
    </Layouts.app>
    """
  end

  defp listed(socket) do
    %{current_person: person, asked: asked, zone: zone} = socket.assigns
    today = People.today(person)
    manager = People.manager_name(person)
    filed = Leave.filed(person, asked[:year], asked[:leave_type])

    assign(socket,
      span: "#{Wording.date(filed.dates.first)} – #{Wording.date(filed.dates.last)}",
      earlier: filed.previous && filtered(filed.previous, filed.leave_type_id),
      later: filed.next && filtered(filed.next, filed.leave_type_id),
      form: to_form(%{"leave_type" => filed.leave_type_id}, as: :filter),
      leave_types: Enum.map(filed.leave_types, &{&1.name, &1.id}),
      requests: Enum.map(filed.requests, &shown(&1, person, today, zone, manager)),
      requests_by_id: Map.new(filed.requests, &{&1.id, &1})
    )
  end

  defp filtered(year, leave_type) do
    ~p"/leave?#{Enum.reject([year: year, leave_type: leave_type], &(elem(&1, 1) in [nil, ""]))}"
  end

  defp shown(request, person, today, zone, manager) do
    request |> Wording.filed(today, zone, manager) |> Parts.revisable(request, person)
  end
end
