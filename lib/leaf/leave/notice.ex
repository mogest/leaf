defmodule Leaf.Leave.Notice do
  @moduledoc """
  Who hears about a change to a request, and what they are told.

  Whoever is to decide a request is sent it, and that message is rewritten as the request moves on,
  so that an administrator who did not decide it does not try to. With no manager still employed
  that is every administrator who is, each sent the same message. Nobody is sent word of what they
  did themselves.

  The requester is sent a message of their own whenever somebody else changes or settles their
  request. Those go under a topic apart, so that rewriting the approvers' messages never reaches
  theirs. An edit notifies nobody, so anything somebody has to act on goes out as a new message.
  """

  alias Leaf.Leave.Request
  alias Leaf.Messaging
  alias Leaf.Messaging.Message
  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.Repo
  alias Leaf.Wording

  @doc "Tells the approvers there is a request to decide."
  @spec filed(Request.t(), Person.t()) :: :ok
  def filed(request, actor) do
    request = read(request)

    ask(request, actor, asked(request))
  end

  @doc """
  Tells the requester their request has changed, and the approvers where it is still to decide.

  A pending request needs deciding afresh, so the approvers are sent it again, and their earlier
  messages say what it asks for now.
  """
  @spec amended(Request.t(), Person.t()) :: :ok
  def amended(request, actor) do
    request = read(request)

    ask_again(request, actor)
    tell(request, actor, "#{actor.name} amended your request. It is now for #{leave(request)}.")
  end

  @doc "Says who decided a request, to the approvers and to the requester."
  @spec decided(Request.t()) :: :ok
  def decided(request) do
    %{reviewed_by: reviewer, status: status} = request = read(request)
    comment = comment(request.review_comment)

    Messaging.revise(
      topic(request),
      %Message{
        text: "#{asked(request)} #{String.capitalize("#{status}")} by #{reviewer.name}#{comment}"
      }
    )

    tell(
      request,
      reviewer,
      "#{reviewer.name} #{status} your request for #{leave(request)}#{comment}"
    )
  end

  @doc "Says who cancelled a request, to the approvers and to the requester."
  @spec cancelled(Request.t(), Person.t()) :: :ok
  def cancelled(request, actor) do
    request = read(request)

    Messaging.revise(topic(request), %Message{
      text: "#{asked(request)} Cancelled by #{actor.name}."
    })

    tell(request, actor, "#{actor.name} cancelled your request for #{leave(request)}.")
  end

  defp ask_again(%{status: :pending, person: person} = request, actor) do
    amended =
      "#{person.name}'s request was amended by #{actor.name}, and is now for #{leave(request)}."

    Messaging.revise(topic(request), %Message{text: amended, path: "/approvals"})
    ask(request, actor, amended)
  end

  defp ask_again(_request, _actor), do: :ok

  defp ask(request, actor, text) do
    {approvers, note} = approvers(request.person)
    message = %Message{text: Enum.join([text | note], " "), path: "/approvals"}

    for approver <- approvers, approver.id != actor.id do
      Messaging.deliver(approver, topic(request), message)
    end

    :ok
  end

  defp tell(%{person_id: id}, %{id: id}, _text), do: :ok

  defp tell(request, _actor, text) do
    Messaging.deliver(request.person, "#{topic(request)}:requester", %Message{
      text: text,
      path: "/leave"
    })
  end

  defp approvers(person) do
    today = People.today(person)

    case People.fetch_manager(person, today) do
      {:ok, manager} -> {[manager], []}
      :error -> person.organisation_id |> People.administrators(today) |> routed(person)
    end
  end

  # One administrator needs no telling that nobody else was sent it.
  defp routed([_first, _second | _rest] = administrators, person) do
    {administrators,
     ["Sent to all #{length(administrators)} administrators, as #{person.name} has no manager."]}
  end

  defp routed(administrators, _person), do: {administrators, []}

  defp asked(request), do: "#{request.person.name} asked for #{leave(request)}."

  defp leave(request) do
    "#{Wording.types(request)}, #{Wording.dates(request)} (#{Wording.amount(request)})"
  end

  defp comment(nil), do: "."
  defp comment(comment), do: ": “#{comment}”"

  defp topic(request), do: "request:#{request.id}"

  defp read(request),
    do: Repo.preload(request, [:person, :reviewed_by, days: :leave_type], force: true)
end
