defmodule LeafWeb.ApprovalsLive do
  @moduledoc """
  What is waiting on you: the requests you are the one to decide, and the deciding of them.

  Who that is comes from `Leaf.Leave.awaiting/1` — the people who report to you, or the whole
  organisation where you administer it, which is §5.3's fallback for a manager who is not there.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave
  alias Leaf.Ledger

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
          <p :if={request.overdrawn} data-tone="wrong">
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
            <button class="button" type="submit" name="decision" value="approve">Approve</button>
            <button type="submit" name="decision" value="decline">Decline</button>
          </.form>
        </li>
      </ol>
      <p :if={@waiting == []}>Nothing is waiting on you.</p>
    </Layouts.app>
    """
  end

  defp queued(socket) do
    assign(
      socket,
      :waiting,
      socket.assigns.current_person |> Leave.awaiting() |> Enum.map(&shown/1)
    )
  end

  defp shown(request) do
    projected = Ledger.projected(request.person, request.days)

    %{
      id: request.id,
      person: request.person.name,
      person_id: request.person_id,
      dates: Wording.dates(request),
      amount: Wording.amount(request),
      detail:
        "#{Wording.types(request)} · requested on #{Wording.day_and_month(request.inserted_at)}",
      note: request.note,
      remaining: Wording.remaining(projected),
      overdrawn: Wording.overdrawn?(projected)
    }
  end

  # Both decisions submit the same form, so either of them carries whatever comment was typed.
  defp decide(socket, decision, id, comment) do
    written =
      with {:ok, request} <- Leave.fetch_request(id),
           do: decided_by(decision).(request, socket.assigns.current_person, comment)

    decided(socket, written)
  end

  defp decided_by("approve"), do: &Leave.approve/3
  defp decided_by("decline"), do: &Leave.decline/3

  defp decided(socket, {:ok, request}) do
    put_flash(socket, :info, "The request is #{request.status}.")
  end

  defp decided(socket, refused) when refused in [:error, {:error, :forbidden}] do
    put_flash(socket, :error, "That is not yours to decide.")
  end

  defp decided(socket, {:error, _changeset}) do
    put_flash(socket, :error, "The decision would not save.")
  end
end
