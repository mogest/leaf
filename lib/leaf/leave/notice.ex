defmodule Leaf.Leave.Notice do
  @moduledoc """
  Who hears about a change to a request, and what they are told.

  Whoever is to decide a request is sent it, and that message is rewritten as the request moves on,
  so that an administrator who did not decide it does not try to. With no manager still employed
  that is every administrator who is, each sent the same message. Nobody is sent word of what they
  did themselves.

  Leave nobody has to approve is approved as it is filed, so its approvers are told of it instead,
  and told again of each change to it.

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

  @doc "Tells the approvers there is a request to decide, or leave they need only know of."
  @spec filed(Request.t(), Person.t()) :: :ok
  def filed(request, actor) do
    request = read(request)

    ask(request, actor, filing(request))
  end

  @doc """
  Tells the requester their request has changed, and the approvers what it is now.

  The approvers' earlier messages are rewritten to say what it is for now. They are sent it again
  where it is pending, since it needs deciding afresh, or approved as it was filed, since nothing
  else tells them of it.
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

    cancelled = "#{cancelling(request)} Cancelled by #{actor.name}."
    Messaging.revise(topic(request), %Message{text: cancelled})
    inform(request, actor, cancelled)

    tell(request, actor, "#{actor.name} cancelled your request for #{leave(request)}.")
  end

  defp ask_again(request, actor) do
    amended = amendment(request, actor)

    Messaging.revise(topic(request), %Message{text: amended, path: path(request)})
    inform(request, actor, amended)
  end

  defp inform(%{status: status, approved_on_filing: on_filing} = request, actor, text)
       when status == :pending or on_filing,
       do: ask(request, actor, text)

  defp inform(_request, _actor, _text), do: :ok

  defp amendment(%{status: :pending} = request, actor), do: now_for(request, actor)

  defp amendment(%{approved_on_filing: true} = request, actor),
    do: "#{filing(request)} Amended by #{actor.name}."

  # Leave brought in from another system has nobody here who approved it.
  defp amendment(%{reviewed_by: nil} = request, actor), do: now_for(request, actor)

  defp amendment(request, actor),
    do: "#{now_for(request, actor)} Approved by #{request.reviewed_by.name}."

  defp now_for(request, actor) do
    "#{request.person.name}'s request was amended by #{actor.name}, and is now for " <>
      "#{leave(request)}."
  end

  defp ask(request, actor, text) do
    {approvers, note} = approvers(request.person)
    message = %Message{text: Enum.join([text | note], " "), path: path(request)}

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

  defp filing(%{approved_on_filing: true} = request),
    do: "#{request.person.name} is away for #{leave(request)}."

  defp filing(request), do: asked(request)

  defp cancelling(%{approved_on_filing: true} = request),
    do: "#{request.person.name}'s leave for #{leave(request)}."

  defp cancelling(request), do: asked(request)

  defp asked(request), do: "#{request.person.name} asked for #{leave(request)}."

  defp path(%{status: :pending}), do: "/approvals"
  defp path(%{status: :cancelled}), do: nil
  defp path(_request), do: "/away"

  defp leave(request) do
    "#{Wording.types(request)}, #{Wording.dates(request)} (#{Wording.amount(request)})"
  end

  defp comment(nil), do: "."
  defp comment(comment), do: ": “#{comment}”"

  defp topic(request), do: "request:#{request.id}"

  defp read(request),
    do: Repo.preload(request, [:person, :reviewed_by, days: :leave_type], force: true)
end
