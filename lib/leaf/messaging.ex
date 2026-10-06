defmodule Leaf.Messaging do
  @moduledoc """
  Messages Leaf sends to people, through whichever channel reaches them.

  Channels are tried in the order configured, and one with no configuration of its own is not
  used. With none configured, a message is logged instead of sent.

  A channel failing loses the message and nothing else: it is logged, and reported where it is not
  merely somebody the channel does not know. Each message sent is recorded against a topic, which
  is what `revise/2` rewrites. Those records are a log of what went out rather than a change to
  anything somebody owns, so they are not in the audit log.
  """

  import Ecto.Query

  require Logger

  alias Leaf.Messaging.Delivery
  alias Leaf.Messaging.Message
  alias Leaf.People.Person
  alias Leaf.Repo

  @doc "Runs `fun` in a task of its own, so that whatever it sends neither fails nor slows the caller."
  @spec async((-> any())) :: :ok
  def async(fun) do
    {:ok, _pid} = Task.Supervisor.start_child(Leaf.Messaging.Tasks, fun)

    :ok
  end

  @doc "Sends a message to a person through the first channel that can reach them."
  @spec deliver(Person.t(), String.t(), Message.t()) :: :ok
  def deliver(person, topic, message) do
    case channels() do
      [] -> Logger.info("Not sent to #{person.name} (#{topic}): #{message.text}")
      channels -> send_first(channels, person, topic, message)
    end
  end

  @doc "Rewrites every message sent under `topic` so far."
  @spec revise(String.t(), Message.t()) :: :ok
  def revise(topic, message) do
    case channels() do
      [] -> Logger.info("Not revised (#{topic}): #{message.text}")
      channels -> revise(topic, message, Map.new(channels, &{&1.name(), &1}))
    end
  end

  defp revise(topic, message, named) do
    Repo.all(
      from delivery in Delivery,
        where: delivery.topic == ^topic and delivery.channel in ^Map.keys(named)
    )
    |> Enum.each(&replace(named[&1.channel], &1, message))
  end

  defp send_first(channels, person, topic, message) do
    {channel, address} = Enum.find_value(channels, &reach(&1, person))

    case channel.send(address, message) do
      {:ok, receipt} ->
        Repo.insert!(%Delivery{
          person_id: person.id,
          channel: channel.name(),
          topic: topic,
          receipt: receipt
        })

        :ok

      {:error, reason} ->
        failed(reason, "#{channel.name()} did not send to #{person.name} at #{address}")
    end
  end

  defp reach(channel, person) do
    case channel.address(person) do
      nil -> nil
      address -> {channel, address}
    end
  end

  defp replace(channel, delivery, message) do
    with {:error, reason} <- channel.replace(delivery.receipt, message) do
      failed(reason, "#{channel.name()} did not revise #{delivery.id} (#{delivery.topic})")
    end
  end

  defp failed(:not_found, what), do: Logger.warning("#{what}: no such account")

  defp failed(reason, what) do
    report = "#{what}: #{inspect(reason)}"
    Logger.error(report)
    Sentry.capture_message(report)

    :ok
  end

  defp channels do
    for channel <- Application.fetch_env!(:leaf, __MODULE__)[:channels],
        Application.get_env(:leaf, channel),
        do: channel
  end
end
