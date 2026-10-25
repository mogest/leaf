defmodule LeafWeb.ApprovalsLive do
  @moduledoc """
  What is waiting on you: the requests you are the one to decide, and the deciding of them.

  Who that is comes from `Leaf.Leave.awaiting/1` — the people who report to you, or the whole
  organisation where you administer it, which is §5.3's fallback for a manager who is not there.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave
  alias Leaf.Ledger
  alias Leaf.People

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Approvals", comments: %{}) |> queued()}
  end

  @impl Phoenix.LiveView
  @role :member
  def handle_event("comment", %{"request_id" => id, "review" => %{"comment" => comment}}, socket) do
    {:noreply, update(socket, :comments, &Map.put(&1, id, comment))}
  end

  @role :member
  def handle_event(
        "decide",
        %{"request_id" => id, "decision" => decision, "review" => %{"comment" => comment}},
        socket
      ) do
    {:noreply, socket |> decide(decision, id, comment) |> queued()}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="approvals" viewer={@viewer}>
      <header>
        <h1>Approvals</h1>
      </header>

      <ol :if={@waiting != []}>
        <li :for={request <- @waiting}>
          <p>
            <.link navigate={~p"/people/#{request.person_id}"}>{request.person}</.link>
          </p>
          <p>{request.detail}</p>
          <p>{request.dates}</p>
          <p>
            <span>{request.amount}</span>
            <span :if={request.remaining} data-tone={request.overdrawn && "wrong"}>
              {request.remaining}
            </span>
          </p>
          <blockquote :if={request.note}>“{request.note}”</blockquote>
          <p :if={request.short} data-tone="wrong">
            {request.short} Only an administrator can approve it.
          </p>
          <p :if={request.overdrawn && !request.short} data-tone="wrong">
            Taking leave in advance. It can still be approved.
          </p>
          <.form
            :let={form}
            for={
              to_form(%{"comment" => @comments[request.id]}, as: :review, id: "decide-#{request.id}")
            }
            id={"decide-#{request.id}"}
            phx-change="comment"
            phx-submit="decide"
          >
            <input type="hidden" name="request_id" value={request.id} />
            <.input field={form[:comment]} type="textarea" label="Comment (optional)" />
            <button
              disabled={!request.approvable?}
              class="button"
              type="submit"
              name="decision"
              value="approve"
            >
              Approve
            </button>
            <button type="submit" name="decision" value="decline">Decline</button>
          </.form>
        </li>
      </ol>
      <p :if={@waiting == []}>Nothing is waiting on you.</p>
    </Layouts.app>
    """
  end

  defp queued(socket) do
    awaiting = Leave.awaiting(socket.assigns.current_person)

    assign(socket,
      waiting: Enum.map(awaiting, &shown(&1, socket.assigns.current_person, socket.assigns.zone)),
      requests_by_id: Map.new(awaiting, &{&1.id, &1})
    )
  end

  defp shown(request, viewer, zone) do
    projected = Ledger.projected(request.person, request.days)

    %{
      id: request.id,
      person: request.person.name,
      person_id: request.person_id,
      dates: Wording.dates(request),
      amount: Wording.amount(request),
      detail:
        "#{Wording.types(request)} · requested on #{Wording.day_and_month(request.inserted_at, zone)}",
      note: request.note,
      remaining: Wording.remaining(projected),
      overdrawn: Wording.overdrawn?(projected),
      short:
        request.person
        |> Ledger.short(request.days, request.id)
        |> Wording.short(People.today(request.person)),
      approvable?: Leave.approvable?(request, viewer)
    }
  end

  # Both decisions submit the same form, so either of them carries whatever comment was typed.
  defp decide(socket, decision, id, comment) do
    written =
      with {:ok, request} <- Map.fetch(socket.assigns.requests_by_id, id),
           do: decided_by(decision).(request, socket.assigns.current_person, comment)

    decided(socket, written)
  end

  defp decided_by("approve"), do: &Leave.approve/3
  defp decided_by("decline"), do: &Leave.decline/3

  defp decided(socket, {:ok, request}) do
    put_flash(socket, :info, "Request #{request.status}.")
  end

  defp decided(socket, {:error, {:stale, since}}) do
    put_flash(socket, :error, Wording.stale(since, "decided"))
  end

  defp decided(socket, {:error, :short}) do
    put_flash(
      socket,
      :error,
      "The balance doesn't cover this, so only an administrator can approve it."
    )
  end

  defp decided(socket, refused) when refused in [:error, {:error, :forbidden}] do
    put_flash(socket, :error, "You can't approve or decline this request.")
  end

  defp decided(socket, {:error, %{errors: [days: _]}}) do
    put_flash(
      socket,
      :error,
      "This request can't be approved: the leave type isn't available on those dates, or the " <>
        "dates fall outside their employment."
    )
  end

  defp decided(socket, {:error, _changeset}) do
    put_flash(socket, :error, "Couldn't save the decision.")
  end
end
