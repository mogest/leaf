defmodule LeafWeb.ApprovalsLive do
  @moduledoc """
  What is waiting on you: the requests you are the one to decide, and the deciding of them.

  Who that is comes from `Leaf.Leave.awaiting/1` — the people who report to you, or the whole
  organisation where you administer it, which is §5.3's fallback for a manager who is not there.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Approvals") |> queued()}
  end

  @impl Phoenix.LiveView
  def handle_event("decide", %{"request_id" => id, "decision" => decision} = params, socket) do
    {:noreply, socket |> decide(decision, id, params["comment"]) |> queued()}
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
            <span>{request.dates}</span>
            <span>{request.amount}</span>
          </p>
          <p>{request.detail}</p>
          <p :if={request.note}>“{request.note}”</p>
          <form id={"decide-#{request.id}"} phx-submit="decide">
            <input type="hidden" name="request_id" value={request.id} />
            <input type="text" name="comment" placeholder="A comment, if you have one" />
            <button class="button" type="submit" name="decision" value="approve">Approve</button>
            <button type="submit" name="decision" value="decline">Decline</button>
          </form>
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
    %{
      id: request.id,
      person: request.person.name,
      person_id: request.person_id,
      dates: Wording.dates(request),
      amount: Wording.amount(request),
      detail:
        "#{Wording.types(request)} · asked on #{Wording.day_and_month(request.inserted_at)}",
      note: request.note
    }
  end

  # Both decisions submit the same form, so either of them carries whatever comment was typed.
  defp decide(socket, decision, id, comment) do
    {:ok, request} = Leave.fetch_request(id)

    decided(socket, decided_by(decision).(request, socket.assigns.current_person, blank(comment)))
  end

  defp decided_by("approve"), do: &Leave.approve/3
  defp decided_by("decline"), do: &Leave.decline/3

  defp decided(socket, {:ok, request}) do
    put_flash(socket, :info, "The request is #{request.status}.")
  end

  defp decided(socket, {:error, :forbidden}) do
    put_flash(socket, :error, "That is not yours to decide.")
  end

  defp decided(socket, {:error, _changeset}) do
    put_flash(socket, :error, "The decision would not save.")
  end

  defp blank(comment) when comment in [nil, ""], do: nil
  defp blank(comment), do: comment
end
