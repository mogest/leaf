defmodule Leaf.MessagingTest do
  # Which channels are configured is application-wide.
  use Leaf.DataCase, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Leaf.Fixtures
  alias Leaf.Leave
  alias Leaf.Messaging.Slack.API
  alias Leaf.People

  @thursday ~D[2026-08-20]
  @friday ~D[2026-08-21]
  @gone ~D[2025-01-01]

  setup do
    Fixtures.workplace()
  end

  defp day(context, date) do
    %{leave_type_id: context.leave_type.id, date: date, amount: "8", unit: :hours}
  end

  defp file(context, actor \\ nil, date \\ @thursday) do
    settled(Leave.request(context.person, actor || context.person, %{days: [day(context, date)]}))
  end

  # The next write looks for what the last one's messages recorded.
  defp settled(result) do
    await_messages()
    result
  end

  defp reload(%{id: id}) do
    {:ok, request} = Leave.fetch_request(id)
    request
  end

  defp link(path), do: "\n<#{LeafWeb.Endpoint.url()}#{path}|Open in Leaf>"

  defp admin(organisation, name, attrs \\ %{}) do
    Fixtures.person(
      Map.merge(%{organisation_id: organisation.id, name: name, role: :admin}, attrs)
    )
  end

  test "with no channel configured, a message is logged and nothing is sent", context do
    reject(&API.post_message/2)
    Logger.put_module_level(Leaf.Messaging, :info)
    on_exit(fn -> Logger.delete_module_level(Leaf.Messaging) end)

    log = capture_log(fn -> file(context) end)

    assert log =~ "Not sent to Ines Vasquez (request:"
    assert log =~ "Rae Halloran asked for Annual leave, Thursday 20 August (8 hours)."
  end

  describe "through Slack" do
    setup do
      Application.put_env(:leaf, Leaf.Messaging.Slack, token: "xoxb-test")
      on_exit(fn -> Application.delete_env(:leaf, Leaf.Messaging.Slack) end)

      test = self()

      stub(API, :lookup_by_email, &{:ok, &1})

      stub(API, :post_message, fn user, text ->
        send(test, {:posted, user, text})
        {:ok, %{"channel" => "D-" <> user, "ts" => "1"}}
      end)

      stub(API, :update, fn channel, "1", text ->
        send(test, {:updated, channel, text})
        :ok
      end)

      :ok
    end

    test "an amendment asks again, and somebody else changing it tells the requester", context do
      %{manager: %{email: manager}, person: %{email: requester}} = context
      {:ok, request} = file(context)

      filed =
        "Rae Halloran asked for Annual leave, Thursday 20 August (8 hours).#{link("/approvals")}"

      assert_received {:posted, ^manager, ^filed}

      {:ok, _amended} =
        settled(Leave.amend(reload(request), context.person, %{days: [day(context, @friday)]}))

      asked_again =
        "Rae Halloran's request was amended by Rae Halloran, and is now for Annual leave, " <>
          "Friday 21 August (8 hours).#{link("/approvals")}"

      assert_received {:updated, "D-" <> ^manager, ^asked_again}
      assert_received {:posted, ^manager, ^asked_again}
      refute_received {:posted, ^requester, _text}

      {:ok, _amended} =
        settled(Leave.amend(reload(request), context.manager, %{days: [day(context, @thursday)]}))

      told =
        "Ines Vasquez amended your request. It is now for Annual leave, Thursday 20 August " <>
          "(8 hours).#{link("/leave")}"

      revised =
        "Rae Halloran's request was amended by Ines Vasquez, and is now for Annual leave, " <>
          "Thursday 20 August (8 hours).#{link("/approvals")}"

      assert_received {:posted, ^requester, ^told}
      assert_received {:updated, "D-" <> ^manager, ^revised}
      refute_received {:posted, ^manager, _text}

      {:ok, _cancelled} = settled(Leave.cancel(reload(request), context.manager))

      cancelled =
        "Ines Vasquez cancelled your request for Annual leave, Thursday 20 August (8 hours)." <>
          link("/leave")

      assert_received {:posted, ^requester, ^cancelled}
    end

    test "with no manager, every administrator employed there is asked, and told who decided",
         context do
      %{organisation: organisation, person: %{email: requester}} = context
      admins = [admin(organisation, "Toma Ferrer"), admin(organisation, "Yusuf Adeyemi")]
      %{email: departed} = admin(organisation, "Mele Tupou", %{employment_end_date: @gone})
      %{email: elsewhere} = admin(Fixtures.organisation(), "Oskar Lind")

      {:ok, person} = People.update_person(context.person, nil, %{manager_id: nil})
      {:ok, request} = file(%{context | person: person})

      filed =
        "Rae Halloran asked for Annual leave, Thursday 20 August (8 hours). " <>
          "Sent to all 2 administrators, as Rae Halloran has no manager.#{link("/approvals")}"

      for %{email: email} <- admins, do: assert_received({:posted, ^email, ^filed})
      refute_received {:posted, ^departed, _text}
      refute_received {:posted, ^elsewhere, _text}

      {:ok, _approved} = settled(Leave.approve(reload(request), hd(admins), "Enjoy"))

      for %{email: email} <- admins do
        assert_received {:updated, "D-" <> ^email,
                         "Rae Halloran asked for Annual leave, Thursday 20 August (8 hours). " <>
                           "Approved by Toma Ferrer: “Enjoy”"}
      end

      approved =
        "Toma Ferrer approved your request for Annual leave, Thursday 20 August (8 hours): " <>
          "“Enjoy”#{link("/leave")}"

      assert_received {:posted, ^requester, ^approved}
    end

    test "a manager who has left leaves the only administrator to decline it", context do
      %{person: %{email: requester}} = context
      %{email: email} = admin = admin(context.organisation, "Toma Ferrer")
      {:ok, _left} = People.update_person(context.manager, nil, %{employment_end_date: @gone})
      {:ok, request} = file(context)

      filed =
        "Rae Halloran asked for Annual leave, Thursday 20 August (8 hours).#{link("/approvals")}"

      assert_received {:posted, ^email, ^filed}

      {:ok, _declined} = settled(Leave.decline(reload(request), admin))

      assert_received {:updated, "D-" <> ^email,
                       "Rae Halloran asked for Annual leave, Thursday 20 August (8 hours). " <>
                         "Declined by Toma Ferrer."}

      declined =
        "Toma Ferrer declined your request for Annual leave, Thursday 20 August (8 hours)." <>
          link("/leave")

      assert_received {:posted, ^requester, ^declined}
    end

    test "a cancellation rewrites the approver's message, and tells the requester if it was not them",
         context do
      %{manager: %{email: manager} = approver, person: %{email: requester}} = context
      {:ok, own} = file(context)
      assert_received {:posted, ^manager, _filed}

      {:ok, _cancelled} = settled(Leave.cancel(reload(own), context.person))

      assert_received {:updated, "D-" <> ^manager,
                       "Rae Halloran asked for Annual leave, Thursday 20 August (8 hours). " <>
                         "Cancelled by Rae Halloran."}

      refute_received {:posted, ^requester, _text}

      {:ok, theirs} = file(context, approver, @friday)
      refute_received {:posted, ^manager, _text}

      {:ok, _approved} = settled(Leave.approve(reload(theirs), approver))

      {:ok, _amended} =
        settled(Leave.amend(reload(theirs), approver, %{days: [day(context, @thursday)]}))

      {:ok, _cancelled} = settled(Leave.cancel(reload(theirs), approver))

      amended =
        "Ines Vasquez amended your request. It is now for Annual leave, Thursday 20 August " <>
          "(8 hours).#{link("/leave")}"

      cancelled =
        "Ines Vasquez cancelled your request for Annual leave, Thursday 20 August (8 hours)." <>
          link("/leave")

      assert_received {:posted, ^requester, ^amended}
      assert_received {:posted, ^requester, ^cancelled}
    end

    test "somebody Slack does not know is skipped with a warning", context do
      stub(API, :lookup_by_email, fn _email -> {:error, "users_not_found"} end)
      reject(&Sentry.capture_message/1)

      log = capture_log(fn -> file(context) end)

      assert log =~
               "slack did not send to Ines Vasquez at #{context.manager.email}: no such account"

      refute_received {:posted, _user, _text}
    end

    test "Slack refusing a message or a rewrite is reported", context do
      test = self()
      stub(Sentry, :capture_message, &send(test, {:reported, &1}))
      {:ok, request} = file(context)

      stub(API, :post_message, fn _user, _text -> {:error, "ratelimited"} end)
      stub(API, :update, fn _channel, _ts, _text -> {:error, "message_not_found"} end)
      log = capture_log(fn -> settled(Leave.approve(reload(request), context.manager)) end)

      assert_received {:reported, revising}
      assert revising =~ ~r/slack did not revise .* \(request:.*\): "message_not_found"/
      assert_received {:reported, sending}

      assert sending ==
               "slack did not send to Rae Halloran at #{context.person.email}: \"ratelimited\""

      assert log =~ revising
      assert log =~ sending
    end
  end
end
