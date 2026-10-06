defmodule Leaf.Messaging.Slack do
  @moduledoc """
  Slack, as a channel: a direct message from the Leaf app to the person.

  A person is found by their email, so there is nothing about Slack to record on them. The bot
  token needs the `chat:write`, `users:read` and `users:read.email` scopes.
  """

  @behaviour Leaf.Messaging.Channel

  alias Leaf.Messaging.Message
  alias Leaf.Messaging.Slack.API

  @impl true
  def name, do: "slack"

  @impl true
  def address(person), do: person.email

  @impl true
  def send(email, message) do
    case API.lookup_by_email(email) do
      {:ok, user_id} -> API.post_message(user_id, text(message))
      {:error, "users_not_found"} -> {:error, :not_found}
      error -> error
    end
  end

  @impl true
  def replace(%{"channel" => channel, "ts" => ts}, message) do
    API.update(channel, ts, text(message))
  end

  defp text(message), do: linked(escaped(message.text), Message.url(message))

  defp linked(text, nil), do: text
  defp linked(text, url), do: "#{text}\n<#{url}|Open in Leaf>"

  defp escaped(text) do
    String.replace(text, ["&", "<", ">"], fn
      "&" -> "&amp;"
      "<" -> "&lt;"
      ">" -> "&gt;"
    end)
  end
end
